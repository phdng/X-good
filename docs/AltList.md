# AltList setup (manual .deb)

If GitHub releases are unavailable or rate-limited, you can supply a local AltList
package for the build.

## Steps

1. Download the AltList release package from the upstream project:
   `https://github.com/opa334/AltList/releases/latest`
2. Save the file as `AltList.deb`.
3. Place the file in `libs/AltList.deb` in this repo, **or** point the setup script
   at it with an environment variable:

   ```bash
   export ALTLIST_DEB_PATH=/absolute/path/to/AltList.deb
   ```

4. Run the setup script as usual:

   ```bash
   bash scripts/setup_altlist.sh
   ```

The script will prefer the local `.deb` file and skip the GitHub API lookup.
