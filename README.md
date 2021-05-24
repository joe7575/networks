# Networks [networks]

A library to build and manage networks based on tubelib2 tubes, pipes, or cables.

**This library is heavily under development. API changes and crashes are likely!**

![networks](https://github.com/joe7575/networks/blob/main/screenshot.png)


### Power Networks

Power networks consists of following node types:

- Generators, nodes providing power
- Consumers, nodes consuming power
- Storage nodes, nodes storing power
- Cables, to build power connections
- Junctions, to build power networks
- Switches, to turn on/off network segments

All storage nodes in a network form a storage system. Storage systems are
required as buffers. Generators "charge" the storage system, consumers
"discharge" the storage system.

Charging the storage system follows a degressive/adaptive charging curve.
When the storage system is 50% full, the charging load is continuously reduced.
This ensures that all generators are loaded in a balanced manner.

Cables, junctions, and switches can be hidden under blocks (plastering)
and opened again with a tool.
This makes power installations in buildings more realistic.
The mod uses a whitelist for filling material. The function 
`networks.register_filling_items` is used to register node names.


### Liquid Networks

tbd.


### Test Nodes

The file `test.lua` includes test nodes of each kind. It can be used to
play with the features and to study the use of `networks`.

- [G] a generator, which provides 20 units of power every 2 s
- [C] a consumer, which need 5 units of power every 2 s

Both nodes can be turned on/off by right-clicking.

- [S] a storage with 500 units capacity
- cable node for power transportation
- junction node for power distribution
- a power switch to turn on/off consumers
- a tool to hide/open cables and junctions


### License

Copyright (C) 2021 Joachim Stolberg  
Code: Licensed under the GNU AGPL version 3 or later. See LICENSE.txt  
Textures: CC BY-SA 3.0  


### Dependencies

Required: tubelib2


### History

**2021-05-23  V0.01**
- First shot

**2021-05-24  V0.02**
- Add switch
- Add tool and hide/open feature
- bug fixes and improvements
