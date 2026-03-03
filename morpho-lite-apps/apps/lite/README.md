# Morpho Lite App

React web app for Morpho Blue and MetaMorpho contracts that's designed to work using only public RPCs－no other infrastructure required.

## Installation

To get started:

```shell
git clone https://github.com/morpho-org/morpho-lite-apps.git
cd morpho-lite-apps/apps/lite
# Install packages and run
pnpm install
pnpm run dev
```

After running the commands above, open [http://localhost:5173/](http://localhost:5173/) in your browser to use the app.

## Configuration

- [.env](/apps/lite/.env) -- Contains API keys and the webpage title (see the [template](/apps/lite/.env.template) for guidance)
- [constants](/apps/lite/src/lib/constants.tsx) -- Defines general constants for the app

  - `APP_DETAILS`: Metadata to show in WalletConnect modal
  - `WORDMARK`: Link to your custom branding, either externally (https://your-website.com/your-logo.svg) or locally (/your-logo.svg) to assets in the [public](/apps/lite/public) folder. "Powered by Morpho" will appear in addition to any custom branding; this is required. Leave blank `""` for standard Morpho branding.
  - `MIN_TIMELOCK`: Vaults with timelocks _lower_ than this number of seconds will not be listed
  - `DEFAULT_CHAIN`: The chain to redirect to when the user navigates to the base url, e.g. lite.morpho.org → lite.morpho.org/polygon/earn
  - `TERMS_OF_USE`: Link to the Terms of Use to show before the user connects their wallet
  - `BANNERS`: A set of banners to show for each chain (optional) -- includes color and a React element

- [curators](/apps/lite/src/lib/curators.ts) -- A curator whitelist to use _in addition_ to the official ones on Full Deployments. A curator is defined by a list of addresses (case-sensitive, checksummed), a name, an image, and an external website url.

To add a new chain, you'll need to update additional values in [constants](/apps/lite/src/lib/constants.tsx), as well as the [wagmi-config](/apps/lite/src/lib/wagmi-config.ts) and [chain icons](/packages/uikit/src/components/chain-icon.tsx).

> [!WARNING]
> Only vault `owner` addresses should be used for whitelisting. Listing or checking against other vault attributes
> (like `curator`) is dangerous as those roles can be assigned without acceptance, i.e. a scammer could assign a
> whitelisted party as their scam's curator, making it appear more legitimate than it is.

## License

Licensed under [AGPL-3.0](/apps/lite/LICENSE). If you fork, deploy, or modify the code herein (particularly for whitelabeling use-cases), please keep the "Powered by Morpho" branding in the top left of the page.
