# Mappy-Continued

A continuation of [Mappy](https://github.com/Mundocani/Mappy) addon for World of Warcraft, originally created by [Mundocani](https://github.com/Mundocani).

Compatible with Midnight and Forever!

Since the original addon seems pretty much abandoned, I've decided to fork and maintain it. I love this addon too much to find a new one, so I've fixed it instead!

I used to say I don't plan on adding new features, but I already added a lot so that no longer stands lol. I still prefer to maintain the currently implemented features with as little modifications of the original codebase as possible, but if you have cool ideas for anything new - ask away! It's still going to be a case-by-case thing though.

## Features

Mappy-Continued is a minimap addon focused on changing the minimap shape into a sleek square.

Other features include:
* Custom square textures (handmade in Photopea :D )
* Resizing of the minimap
* Option to move the minimap via Edit Mode only
* Option to move the minimap via addon settings only
* Automatic stacking of minimap buttons along the minimap OR screen
* Option to show minimap buttons only on mouseover
* Pretty-ing the stock Calendar, Mail and Tracking buttons to actually look like buttons
* Zooming in and out with the mouse wheel
* Alpha settings, separate for combat, movement and default state
* Option to hide map icons when the minimap is at 0% alpha
* Option to hide the quest/WQ/archaeology edge pattern
* Option to fade quest/WQ/archaeology areas with the minimap alpha
* Profiles (including being able to set a profile for mounting, dungeon etc)
* Gathering overlay support for GatherMate
* Compatibility with MinimapButtonBag Reborn
* Compatibility with FarmHud
* ~~Bigger and/or blinking gathering nodes~~ - **Broken since 12.0.7, working on a workaround**
* ~~Classic-style dot for gathering nodes~~ - **Broken since 12.0.7, working on a workaround**
* Player coordinates

## Slash commands

`/mappy` - Opens options in the Interface window

`/mappy help` - Shows a list of available commands

`/mappy default` - Loads the default profile

`/mappy save settingsname` - Saves the settings under the name settingsname

`/mappy load settingsname` - Loads the settings

`/mappy settingsname` - Shorthand version of /mappy load

`/mappy ghost` - Mouse clicks in the minimap will be passed through to the background

`/mappy unghost` - Mouse clicks work as usual

`/mappy corner TOPLEFT|TOPRIGHT|BOTTOMLEFT|BOTTOMRIGHT` - Sets the starting corner for button stacking

`/mappy reset` - Resets all settings and profiles

`/mappy unlock` - Unlocks the minimap for dragging

`/mappy lock` - Locks the minimap, preventing its movement

`/mappy reload` - Reload Mappy if something doesn't look right (buttons overlapping etc)

## Authors

* [Mundocani](https://github.com/Mundocani) (original author of Mappy)
* [LynchburgJack](https://github.com/LynchburgJack) (maintainer of [Mappy-Shadowlands](https://github.com/LynchburgJack/Mappy-Shadowlands) fork)
* [Shushuda](https://github.com/Shushuda) (maintainer of this fork - [Mappy-Continued](https://github.com/Shushuda/Mappy-Continued))
* [wealdly](https://github.com/wealdly) (bugfixes and performance improvements)
* [Little-Bunny-FuFu](https://github.com/Little-Bunny-FuFu) (bugfixes)
* [Zuz666](https://github.com/Zuz666) (bugfixes and improvements)

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details
