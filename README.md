## <img width="45" height="45" alt="image" src="logo.png" />  Enhanced Package Manager (EPM)
A solution for Android and Termux trying to bridge the gap between apk GUI apps and pkg CLI binaries into one single package manager. 
It leverages the Aptoide repos as well as the pkg backagend for CLI binaries.

**Features**
- `epm install <name>` Installs a apk or pkg pacakges by name
- `epm remove <name>` Removes an existant apk or pkg package by name
- `epm about` Shows a brief information about this project
- `epm clean` Cleans any grabadge apk files if the download process was interrupted or you want to remove the downloaded files
- `epm help` Shows the available commands and what each one does
- `epm list` Lists all apk pacakges and cli ones on the system together
- `epm search <name>` Searches for a package by that name on both Termux and Aptoide repos showing name, and provider

**Root features for GUI pacakges (apk)**
- If `epm install/remove` is called on a NON rooted device it will launch the default Android's package dialog and you would have to proceed manually
- If `epm install/remove` is called on a ROOTED device, it will leverage Android's pacakaging system `pm` for those oparations

**Warnings and Precautions**
Always be careful about what you install as the Aptoide repo is not completely safe from malisious apps nor was any repo historically on other systems as well
so use responsibly and always do `epm search` to check the provider name of the package to be sure its what you want.
