## List of desired changes
- art command will error if there is no ArtSource folder in the project.
  we want it to instead ask the user if they wanted it created. If yes generate the folders for them

- If there is an error during install. we should rollback all files so we dont leave scripts in a broken state.

- If the project is not a git repo offer to init one, prompt for a commit message, that can be bypassed. If bypassed it will be filled with a default message.

- Errors should not throw exception, but rather colorized text that states the error and fixes where applicable.

- On repo init script we should remove all files that are newly ignored to help newer users that added commonly ignored files like build files by mistake.

- Make sure help output for commands are detailed and have all available flags explained 

- I want to shrink the payload further. Explain the reason for keeping all these .runtime scripts and if we can merge scripts any further.

- build needs to handle being ran in a blueprint project and fails gracefully with info on why.

- Table of contents creation through the vscode bridge isnt working:/ we have to fix it.

- The docs server start commands should warn the user if there is any instance running either in a background or in another terminal and give them the option to abort. 

- Running ue check results in "Error: Docs validation failed:
  Unprocessed TOC marker remains in: C:\Users\Rim28\Projects\UEToolSetTest\Docs\Test\Page-Test.md
  Unprocessed TOC marker remains in: C:\Users\Rim28\Projects\UEToolSetTest\Docs\Test\README.md" Im not sure whats going on here. We need to look into this.

- If ue docs spawns more than one sever (user ignored multi server warning) we need to keep track of all of them not just the last one. ue docs stop should stop all servers.

- In reading the exe certificate guide it mentions having a legal company and that i have to buy one. Are there any free options?
