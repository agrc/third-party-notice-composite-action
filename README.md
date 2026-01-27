# 3rd party notice composite action

A GitHub Action that creates a 3rd party notice file. It is placed in the default vite output location in `./public/ThirdPartyNotices.txt`.

## Usage

```yml
name: Release Events

on:
  release:
    types: [published]

permissions:
  contents: write

jobs:
  deploy-prod:
    name: Deploy to production
    runs-on: ubuntu-latest
    environment:
      name: prod
      url: https://gis.utah.gov
    if: github.event.release.prerelease == false || inputs.environment == 'prod'

    steps:
      - name: 📃 Configure 3rd party notice
        uses: agrc/third-party-notice-composite-action@v1
```

## Configuration

By default this action creates configuration that reads from a root level `package.json` and writes the result to `./public/ThirdPartyNotices.txt`. You can view the [basic configuration file](./config.json) within the repository. If your repository diverges from these defaults, use the options below to fit your use case.

### YML Action Options

1. *inputs*: an array of locations for `package.json` files. Use this to add extra `package.json` files. When using this input, the defaults are replaced.

   ```yml
   inputs:
     - package.json
     - functions/package.json
   ```

1. *output*: a string of where to save the 3rd party notice file if the default is not desired.

   ```yml
   output: ./dist/ThirdPartyNotices.txt
   ```

1. *replacements*: an array of objects with a package and license property. If the tool cannot determine the license location or if multiple are found, use this input to define the correct locations. When using this input, the defaults are merged.

   ```yml
   replacements:
     - package: @esri/arcgis-rest-fetch
       license: https://raw.githubusercontent.com/Esri/arcgis-rest-js/main/LICENSE
   ```

1. *exclude*: an array of regex patterns for packages to exclude from the notice. By default, `@ugrc` scoped packages are excluded since we own them. When using this input, the defaults are replaced.

   ```yml
   exclude:
     - /^@ugrc\/.*$/
     - /^@your-package\/.*$/
   ```

### Full example

```yml
- name: 📃 Configure 3rd party notice
  uses: agrc/third-party-notice-composite-action@v1
  with:
    inputs:
      - package.json
      - functions/package.json
    output: ./dist/ThirdPartyNotices.txt
    replacements:
      - package: @esri/arcgis-rest-fetch
        license: https://raw.githubusercontent.com/Esri/arcgis-rest-js/main/LICENSE
    exclude:
      - /^@ugrc\/.*$/
      - /^@your-package\/.*$/
```

## Manual execution

The action will add the configuration it used to the summary and can be used with the following node commands.

```sh
pnpm dlx generate-license-file --config glf.json
```

or

```sh
npx generate-license-file --config glf.json
```
