# Control Prolog Adventure

## Overview
This project is a text-based adventure game inspired by the 2019 game "Control". It is implemented in Prolog and features a rich narrative, engaging combat mechanics, and interactive dialogue with non-player characters (NPCs). Players will explore a mysterious environment, solve puzzles, and uncover the secrets of the Federal Bureau of Control.

## Project Structure
The project is organized into the following files:

- **src/combat.pl**: Contains the rules and mechanics for combat within the game, including health management and enemy actions.
  
- **src/dialogue.pl**: Manages dialogue interactions between the player and NPCs, allowing for dynamic conversations based on player actions and inventory.
  
- **src/engine.pl**: The core engine of the game that handles the main game loop, command parsing, and action dispatching based on player input.
  
- **src/infection.pl**: Contains rules related to infection mechanics, detailing how characters can be affected by supernatural elements in the game.
  
- **src/map.pl**: Defines the game's map structure, including room connections, descriptions, and navigation rules for player movement.
  
- **src/objects.pl**: Manages game objects, including items that players can interact with, pick up, or use, along with their properties and behaviors.
  
- **src/parser.pl**: Contains the command parser that interprets player input and translates it into game actions.
  
- **src/start.pl**: Initializes the game, setting up the starting state, displaying introductory text, and preparing the player for their adventure.
  
- **src/world.pl**: Contains world-building elements, including setting, lore, and overarching rules that govern the game environment.

## Getting Started
To run the game, ensure you have a Prolog interpreter installed. Load the `src/start.pl` file and execute the `start.` command to begin your adventure.

## Gameplay Instructions
- Use standard Prolog syntax to enter commands.
- Movement: Use commands like `go north`, `go south`, etc.
- Interact with objects using `take(Object)` or `drop(Object)`.
- Engage in dialogue with NPCs using `talk(NPC)`.
- Combat can be initiated with `attack(Enemy)`.

## Contributing
Feel free to contribute to the project by adding new features, improving existing mechanics, or fixing bugs. Please submit a pull request with your changes.

## License
This project is open-source and available for anyone to use and modify.