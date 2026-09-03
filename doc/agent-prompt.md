# Agent prompt: install the Reqall widget for Omarchy

Paste the block below into Claude Code, Codex, or any agent with shell access on your Omarchy machine.

```text
Install the Reqall widget for the Omarchy bar and get it signed in.

1. Run: omarchy plugin add https://github.com/ReqallSystem/omarchy_plugin.git --enable --yes
   Then confirm with: omarchy plugin list | grep reqall.memory
   If the plugin is already installed, run `omarchy plugin update reqall.memory --yes` instead.
2. Check for an existing Reqall API key, in this order: the REQALL_API_KEY
   environment variable, ~/.config/reqall/env, ~/.config/reqall/config.json.
   If one exists, skip to step 4.
3. Otherwise ask me for a key. I can create one at
   https://www.reqall.net/dashboard#keys (sign up or sign in first at
   https://www.reqall.net/auth/login). Never guess or fabricate a key.
   Save what I give you with:
     mkdir -p ~/.config/reqall
     printf 'export REQALL_API_KEY=%s\n' "<key>" >> ~/.config/reqall/env
     chmod 600 ~/.config/reqall/env
   Do not print the key back to me or write it anywhere else.
4. Run: omarchy-shell reqall.memory refresh
   then: omarchy-shell reqall.memory open
   and tell me whether the panel shows "Signed in" or an error message.
5. Optional: I can change the icon with
   omarchy bar set reqall.memory barIcon brain|head-cog|emoji
   and move it with omarchy bar move reqall.memory --section left|center|right.
```
