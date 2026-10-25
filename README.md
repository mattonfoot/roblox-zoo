# Zoo Tycoon (Roblox)

A Roblox game where you run your own zoo. Buy baby animals, keep them fed so they grow up, and earn coins from visitors who come to see your adult animals. Unlock more pens, breed animals, and fill your **Zoo Book** by raising every species.

## How to play

1. You get your own zoo plot when you join (up to 6 players per server).
2. Walk up to a pen's sign and press **E** to manage it.
3. Buy a baby animal. Babies grow into juveniles and then adults, but **only while they're fed**.
4. Feed your pens (or use **Feed all pens**). Food runs out after about 2 minutes. Hungry animals stop growing and stop earning.
5. Adult animals earn coins every second from visitors.
6. Two well-fed adults in a pen with space can have a baby.
7. Sell animals for coins (adults sell for much more than babies).
8. The first time you raise each species to adult, it's added to your Zoo Book with a big coin bonus. Raise all 8 to complete the game.

### Animals

| Animal   | Price  | Grows in | Adult income | Sells for |
|----------|-------:|---------:|-------------:|----------:|
| Rabbit   | 40     | 45s      | 1/s          | 90        |
| Penguin  | 120    | 75s      | 3/s          | 260       |
| Goat     | 300    | 100s     | 6/s          | 600       |
| Zebra    | 700    | 140s     | 12/s         | 1,400     |
| Panda    | 1,500  | 180s     | 25/s         | 3,000     |
| Lion     | 3,000  | 240s     | 45/s         | 6,000     |
| Giraffe  | 6,000  | 300s     | 80/s         | 12,000    |
| Elephant | 12,000 | 360s     | 150/s        | 24,000    |

Each pen holds up to 3 animals of one kind. You start with 150 coins and 2 free pens; 6 more pens can be unlocked. All numbers live in `src/shared/Config.lua`.

## Running it

The game is built entirely from code: the map, pens and animal models are all made of parts at runtime, so no uploaded assets are needed.

### Quickest: open the included place file

Open `RobloxZoo.rbxlx` (in the repo root) in Roblox Studio and press **Play**, or use **File → Publish to Roblox** to play it on your phone. If you change the code, rebuild this file with Option A.

### Option A: build a place file

1. Install [Rojo](https://rojo.space) 7.4 (or run `rokit install`).
2. `rojo build default.project.json -o RobloxZoo.rbxlx`
3. Open `RobloxZoo.rbxlx` in Roblox Studio and press **Play**.

### Option B: live sync

1. Install the Rojo plugin in Studio.
2. Run `rojo serve` in this folder.
3. In Studio, open a new Baseplate, connect via the Rojo plugin, and press **Play**. (You can delete the default Baseplate; the game makes its own ground.)

### Saving

Progress saves with DataStores. To save in Studio, publish the place and turn on **Game Settings → Security → Enable Studio Access to API Services**. Without that, the game still runs and tells you progress won't be kept.

## Code layout

```
src/
  shared/              -> ReplicatedStorage.Shared
    Config.lua           Animals, prices, growth and economy settings
    AnimalBuilder.lua    Builds blocky animal models from parts
  server/              -> ServerScriptService.Server
    Main.server.lua      Entry point
    ZooService.lua       Plots, pens, feeding, growth, breeding, income, actions
    WorldBuilder.lua     Ground, road, plots, pens, fences, signs
    DataService.lua      Loading/saving with DataStores
  client/              -> StarterPlayerScripts.Client
    AnimalAnimator.client.lua  Builds and walks animal models on each client
    ZooUI.client.lua           HUD, pen manager, Zoo Book, notifications
```

The server owns all game state and validates every action. Each animal is a small tagged marker on the server holding its species, stage and wander target; clients build the animal models and animate them, which keeps network traffic low.
