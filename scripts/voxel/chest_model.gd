class_name ChestModel
extends RefCounted
## Chests are blocks like Beta 1.7.3's (Blocks._chest): a full cube drawn
## with terrain.png's chest tiles (top and bottom 25, sides 26, a single
## chest's front 27; a large chest's front 41 / 42 and back 58 / 57 by
## half). A large chest is two blocks, its halves (Part).

enum Part { SINGLE, LEFT, RIGHT }
## LEFT is the half on the left when looking at the front (its partner on
## its right, ChestBehavior.right_of).
