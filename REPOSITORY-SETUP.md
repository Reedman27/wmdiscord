# Publishing the archived source repository

This source bundle is prepared for Git. It contains no remote and does not publish anything automatically.

## Create the first commit

After extracting the archive, enter the project directory. Configure your own Git identity if it is not already configured, then commit the staged source:

```sh
git config user.name "Your Name"
git config user.email "you@example.com"
git commit -m "Archive WMDiscord 0.3.2"
```

## Push to GitHub

Create a **public, empty** GitHub repository named `WMDiscord`. Do not initialize it with a README, license, or `.gitignore` because those files are already in this source tree.

Then connect and push:

```sh
git remote add origin https://github.com/YOUR-USERNAME/WMDiscord.git
git push -u origin main
```

Replace `YOUR-USERNAME` with your GitHub username.

## Archive it and leave forks available

After confirming the public repository contains the expected source and GPL-2.0-only license, open the repository's **Settings → General → Danger Zone → Archive this repository** and confirm the archive action.

Archiving makes the repository read-only. Public repositories remain forkable, so others can continue development in their own forks. See the [GitHub documentation on archiving repositories](https://docs.github.com/en/repositories/archiving-a-github-repository/archiving-repositories).

Suggested repository description:

> Archived experimental GNUstep/Objective-C Discord voice overlay for X11 and Window Maker. GPL-2.0-only; forks welcome.

Suggested topics: `objective-c`, `gnustep`, `window-maker`, `x11`, `discord`, `linux`, `voice-overlay`.
