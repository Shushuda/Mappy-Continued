# Mappy-Continued

A continuation of [Mappy](https://github.com/Mundocani/Mappy) addon for World of Warcraft, originally created by [Mundocani](https://github.com/Mundocani).

Compatible with Midnight!

Since the original addon seems pretty much abandoned, I've decided to fork and maintain it. I love this addon too much to find a new one, so I've fixed it instead!

Please bear in mind that I'm not planning on adding new features nor refactoring the code. I want to maintain the currently implemented features with as little modifications of the original codebase as possible. There will be some dirty hacks, which I might pretty-up later.

I _might_ add some new things if you ask for any, but it's going to be a case-by-case thing.

## Features

Mappy-Continued is a minimap addon focused on changing the minimap shape into a sleek square.

Other features include:
* Resizing of the minimap
* Option to move the minimap via Edit Mode only
* Option to move the minimap via addon settings only
* Automatic stacking of minimap buttons along the minimap OR screen
* Pretty-ing the stock Calendar, Mail and Tracking buttons to actually look like buttons
* Zooming in and out with the mouse wheel
* Alpha settings, separate for combat, movement and default state
* Profiles (including being able to set a profile for mounting, dungeon etc)
* Gathering overlay support for Gatherer and GatherMate
* Compatibility with MinimapButtonBag Reborn
* Compatibility with FarmHud
* Bigger and/or blinking gathering nodes
* Classic-style dot for gathering nodes
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

* [Mundocani](https://github.com/Mundocani) (original author)
* [LynchburgJack](https://github.com/LynchburgJack) (maintainer of [Mappy-Shadowlands](https://github.com/LynchburgJack/Mappy-Shadowlands) fork)
* [Shushuda](https://github.com/Shushuda) (maintainer of this fork - [Mappy-Continued](https://github.com/Shushuda/Mappy-Continued))

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details
