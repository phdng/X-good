# AltList setup (build from source)

AltList does not provide a prebuilt framework download, so the setup script builds
the framework from source and installs the outputs into Theos.

## Steps

1. Ensure Xcode and the command line tools are installed on the build machine.
2. Run the setup script as usual:

   ```bash
   bash scripts/setup_altlist.sh
   ```

The script clones the AltList repository, builds the framework with `xcodebuild`,
and then copies the resulting framework and headers into Theos.
