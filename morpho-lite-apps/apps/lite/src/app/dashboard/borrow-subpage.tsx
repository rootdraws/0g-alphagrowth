import { AccrualPosition } from "@morpho-org/blue-sdk";
import { restructure } from "@morpho-org/blue-sdk-viem";
import { metaMorphoFactoryAbi } from "@morpho-org/uikit/assets/abis/meta-morpho-factory";
import { morphoAbi } from "@morpho-org/uikit/assets/abis/morpho";
import useContractEvents from "@morpho-org/uikit/hooks/use-contract-events/use-contract-events";
import {
  marketHasDeadDeposit,
  readAccrualVaults,
  readAccrualVaultsStateOverride,
} from "@morpho-org/uikit/lens/read-vaults";
import { CORE_DEPLOYMENTS, getContractDeploymentInfo } from "@morpho-org/uikit/lib/deployments";
import { Token } from "@morpho-org/uikit/lib/utils";
import { useMemo } from "react";
import { useOutletContext } from "react-router";
import { type Address, erc20Abi, type Chain, zeroAddress, type Hex } from "viem";
import { useAccount, useReadContract, useReadContracts } from "wagmi";

import { BorrowPositionTable, BorrowTable } from "@/components/borrow-table";
import { CtaCard } from "@/components/cta-card";
import { useMarkets } from "@/hooks/use-markets";
import * as Merkl from "@/hooks/use-merkl-campaigns";
import { useMerklOpportunities } from "@/hooks/use-merkl-opportunities";
import { useTopNCurators } from "@/hooks/use-top-n-curators";
import { type DisplayableCurators, getDisplayableCurators } from "@/lib/curators";
import { getDeploylessMode, getShouldEnforceDeadDeposit } from "@/lib/overrides";
import { getTokenURI } from "@/lib/tokens";
import { zerog } from "@morpho-org/uikit/lib/chains/zerog";

const ZEROG_VAULTS: Address[] = [
  "0x6003EEe8e9E8b7C72149B16cd88DEA6eeB4681E3",
  "0xe29AA6Cd4C2245f7Eb52386E28D82Fc0DE2c32dC",
];

const ZEROG_MARKET_IDS: Hex[] = [
  "0x22056ed6318ee3403025f5ef17c4ab40e321538fbfa7e3ae9d3db0dde0de9b5d",
  "0x8cf401e68e3ffaf1320f05a77b45d468b6859c50d57a5b4a0799e9cb85612785",
  "0x4623ffb46148925715620112cfc92314ba37b47ab0cca42a6337fbf9582ca629",
];

const STALE_TIME = 5 * 60 * 1000;

// This cannot be inlined because TanStack needs a stable reference to avoid re-renders.
function restructurePositions(data: (readonly [bigint, bigint, bigint])[]) {
  return data.map((x) => restructure(x, { abi: morphoAbi, name: "position", args: ["0x", "0x"] }));
}

export function BorrowSubPage() {
  const { status, address: userAddress } = useAccount();
  const { chain } = useOutletContext() as { chain?: Chain };
  const chainId = chain?.id;

  const shouldUseDeploylessReads = getDeploylessMode(chainId) === "deployless";
  const shouldEnforceDeadDeposit = getShouldEnforceDeadDeposit(chainId);

  const [morpho, factory, factoryV1_1] = useMemo(
    () => [
      getContractDeploymentInfo(chainId, "Morpho"),
      getContractDeploymentInfo(chainId, "MetaMorphoFactory"),
      getContractDeploymentInfo(chainId, "MetaMorphoV1_1Factory"),
    ],
    [chainId],
  );

  const borrowingRewards = useMerklOpportunities({ chainId, side: Merkl.CampaignSide.BORROW, userAddress });

  // MARK: Index `MetaMorphoFactory.CreateMetaMorpho` on all factory versions to get a list of all vault addresses
  const fromBlock = factory?.fromBlock ?? factoryV1_1?.fromBlock;
  const {
    logs: { all: createMetaMorphoEvents },
    fractionFetched,
  } = useContractEvents({
    chainId,
    abi: metaMorphoFactoryAbi,
    address: factoryV1_1 ? [factoryV1_1.address].concat(factory ? [factory.address] : []) : [],
    fromBlock,
    toBlock: "finalized",
    reverseChronologicalOrder: true,
    eventName: "CreateMetaMorpho",
    strict: true,
    query: { enabled: chainId !== undefined && fromBlock !== undefined },
  });
  const isZerog = chainId === zerog.id;
  const vaultAddresses = useMemo(
    () => isZerog ? ZEROG_VAULTS : createMetaMorphoEvents.map((ev) => ev.args.metaMorpho),
    [isZerog, chainId, createMetaMorphoEvents],
  );

  // MARK: Fetch additional data for whitelisted vaults
  const curators = useTopNCurators({ n: "all", verifiedOnly: true, chainIds: [...CORE_DEPLOYMENTS] });
  const { data: vaultsData } = useReadContract({
    chainId,
    ...readAccrualVaults(
      morpho?.address ?? "0x",
      vaultAddresses,
      curators.flatMap(
        (curator) =>
          curator.addresses?.filter((entry) => entry.chainId === chainId).map((entry) => entry.address as Address) ??
          [],
      ),
      // @ts-expect-error function signature overloading was meant for hard-coded `true` or `false`
      shouldUseDeploylessReads,
    ),
    stateOverride: shouldUseDeploylessReads ? undefined : [readAccrualVaultsStateOverride()],
    query: {
      enabled: chainId !== undefined && (isZerog || fractionFetched > 0.99) && !!morpho?.address,
      staleTime: STALE_TIME,
      gcTime: Infinity,
      notifyOnChangeProps: ["data"],
    },
  });

  const marketIds = useMemo(() => {
    if (isZerog) return ZEROG_MARKET_IDS;

    const filteredAllocationMarketIds = (vaultsData ?? []).flatMap((vd) =>
      vd.allocations
        .filter((alloc) => {
          const isEnabled = alloc.config.enabled;
          const isDeadDepositStateValid = !shouldEnforceDeadDeposit || marketHasDeadDeposit(vd, alloc.id);

          return isEnabled && isDeadDepositStateValid;
        })
        .map((alloc) => alloc.id),
    );
    return [...new Set(filteredAllocationMarketIds)];
  }, [isZerog, shouldEnforceDeadDeposit, vaultsData]);
  const markets = useMarkets({ chainId, marketIds, staleTime: STALE_TIME, fetchPrices: true });
  const marketsArr = useMemo(() => {
    const marketsArr = Object.values(markets).filter(
      (market) =>
        (isZerog || market.totalSupplyAssets > 0n) &&
        ![market.params.collateralToken, market.params.loanToken, market.params.irm, market.params.oracle].includes(
          zeroAddress,
        ),
    );
    marketsArr.sort((a, b) => {
      const primary = a.params.loanToken.localeCompare(b.params.loanToken);
      const secondary = a.liquidity > b.liquidity ? -1 : 1;
      return primary === 0 ? secondary : primary;
    });
    return marketsArr;
  }, [isZerog, markets]);
  const marketVaults = useMemo(() => {
    const map = new Map<
      Hex,
      { name: string; address: Address; totalAssets: bigint; curators: DisplayableCurators }[]
    >();

    if (isZerog) {
      const zerogCurators = getDisplayableCurators(
        { owner: "0x5304ebB378186b081B99dbb8B6D17d9005eA0448" as Address, curator: zeroAddress, guardian: zeroAddress, address: zeroAddress },
        curators,
        chainId,
      );
      const vaultByLoan: Record<string, { name: string; address: Address }> = {
        "0x1f3aa82227281ca364bfb3d253b0f1af1da6473e": { name: "0g USDC Vault", address: ZEROG_VAULTS[0] },
        "0x1cd0690ff9a693f5ef2dd976660a8dafc81a109c": { name: "w0g Vault", address: ZEROG_VAULTS[1] },
      };
      for (const market of Object.values(markets)) {
        const vault = vaultByLoan[market.params.loanToken.toLowerCase()];
        if (vault) {
          map.set(market.params.id, [{
            ...vault,
            totalAssets: 0n,
            curators: zerogCurators,
          }]);
        }
      }
    } else {
      vaultsData?.forEach((vaultData) => {
        vaultData.allocations.forEach((allocation) => {
          if (!allocation.config.enabled || allocation.position.supplyShares === 0n) return;

          if (!map.has(allocation.id)) {
            map.set(allocation.id, []);
          }
          map.get(allocation.id)!.push({
            name: vaultData.vault.name,
            address: vaultData.vault.vault,
            totalAssets: vaultData.vault.totalAssets,
            curators: getDisplayableCurators({ ...vaultData.vault, address: vaultData.vault.vault }, curators, chainId),
          });
        });
      });
    }

    return map;
  }, [isZerog, markets, vaultsData, curators, chainId]);

  const { data: erc20Symbols } = useReadContracts({
    contracts: marketsArr
      .map((market) => [
        { chainId, address: market.params.collateralToken, abi: erc20Abi, functionName: "symbol" } as const,
        { chainId, address: market.params.loanToken, abi: erc20Abi, functionName: "symbol" } as const,
      ])
      .flat(),
    allowFailure: true,
    query: { staleTime: Infinity, gcTime: Infinity },
  });

  const { data: erc20Decimals } = useReadContracts({
    contracts: marketsArr
      .map((market) => [
        { chainId, address: market.params.collateralToken, abi: erc20Abi, functionName: "decimals" } as const,
        { chainId, address: market.params.loanToken, abi: erc20Abi, functionName: "decimals" } as const,
      ])
      .flat(),
    allowFailure: true,
    query: { staleTime: Infinity, gcTime: Infinity },
  });

  const { data: positionsRaw, refetch: refetchPositionsRaw } = useReadContracts({
    contracts: marketsArr.map(
      (market) =>
        ({
          chainId,
          address: morpho?.address ?? "0x",
          abi: morphoAbi,
          functionName: "position",
          args: userAddress ? [market.id, userAddress] : undefined,
        }) as const,
    ),
    allowFailure: false,
    query: {
      staleTime: 1 * 60 * 1000,
      gcTime: Infinity,
      enabled: !!morpho,
      select: restructurePositions,
    },
  });

  const positions = useMemo(() => {
    if (marketsArr.length === 0 || positionsRaw === undefined || userAddress === undefined) {
      return undefined;
    }

    const map = new Map<Hex, AccrualPosition>();
    positionsRaw?.forEach((positionRaw, idx) => {
      const market = marketsArr[idx];
      map.set(market.id, new AccrualPosition({ user: userAddress, ...positionRaw }, market));
    });
    return map;
  }, [marketsArr, positionsRaw, userAddress]);

  const tokens = useMemo(() => {
    const map = new Map<Address, Token>();
    marketsArr.forEach((market, idx) => {
      const collateralTokenSymbol = erc20Symbols?.[idx * 2].result;
      const loanTokenSymbol = erc20Symbols?.[idx * 2 + 1].result;
      map.set(market.params.collateralToken, {
        address: market.params.collateralToken,
        symbol: collateralTokenSymbol,
        decimals: erc20Decimals?.[idx * 2].result,
        imageSrc: getTokenURI({ symbol: collateralTokenSymbol, address: market.params.collateralToken, chainId }),
      });
      map.set(market.params.loanToken, {
        address: market.params.loanToken,
        symbol: loanTokenSymbol,
        decimals: erc20Decimals?.[idx * 2 + 1].result,
        imageSrc: getTokenURI({ symbol: loanTokenSymbol, address: market.params.loanToken, chainId }),
      });
    });
    return map;
  }, [marketsArr, erc20Symbols, erc20Decimals, chainId]);

  if (status === "reconnecting") return undefined;

  const userMarkets = marketsArr.filter((market) => positions?.get(market.id)?.collateral ?? 0n > 0n);

  return (
    <div className="flex min-h-screen flex-col px-2.5 pt-16">
      {status === "disconnected" ? (
        <div className="bg-linear-to-b flex w-full flex-col from-transparent to-white/[0.03] px-8 pb-20 pt-8">
          <CtaCard
            className="md:w-7xl flex flex-col gap-4 md:mx-auto md:max-w-full md:flex-row md:items-center md:justify-between"
            bigText="Provide collateral to borrow any asset"
            littleText="Connect wallet to get started"
            videoSrc={{
              mov: "https://cdn.morpho.org/v2/assets/videos/borrow-animation.mov",
              webm: "https://cdn.morpho.org/v2/assets/videos/borrow-animation.webm",
            }}
          />
        </div>
      ) : (
        userMarkets.length > 0 && (
          <div className="bg-linear-to-b lg:pt-22 flex h-fit w-full flex-col items-center from-transparent to-white/[0.03] pb-20">
            <div className="text-primary-foreground w-full max-w-7xl px-2 lg:px-8">
              <BorrowPositionTable
                chain={chain}
                markets={userMarkets}
                tokens={tokens}
                positions={positions}
                borrowingRewards={borrowingRewards}
                refetchPositions={refetchPositionsRaw}
              />
            </div>
          </div>
        )
      )}
      {/*
      Outer div ensures background color matches the end of the gradient from the div above,
      allowing rounded corners to show correctly. Inner div defines rounded corners and table background.
      */}
      <div className="flex grow flex-col bg-white/[0.03]">
        <div className="bg-linear-to-b from-background to-primary flex h-full grow justify-center rounded-t-xl pb-16 pt-8">
          <div className="text-primary-foreground w-full max-w-7xl px-2 lg:px-8">
            <BorrowTable
              chain={chain}
              markets={marketsArr}
              tokens={tokens}
              marketVaults={marketVaults}
              borrowingRewards={borrowingRewards}
              refetchPositions={refetchPositionsRaw}
            />
          </div>
        </div>
      </div>
    </div>
  );
}
