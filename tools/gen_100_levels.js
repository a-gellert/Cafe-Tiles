const fs = require('fs');
const { LevelBuilder } = require('./level_builder');

const generators = [
  // 1. Pagoda
  (b) => {
    b.box('A', 1, 2, 6, 5);
    b.box('B', 0, 1, 7, 2);
    b.box('B', 1, 4, 5, 2);
    b.box('C', 0, 0, 6, 2);
    b.box('C', 1, 3, 4, 2);
    b.box('D', 1, 1, 3, 3);
    b.plot('E', 1, 1);
    b.stack(3, 1, 4);
  },
  // 2. Parthenon
  (b) => {
    b.box('A', 0, 5, 8, 2);
    b.line('A', 1, 1, 6, 1);
    b.box('B', 1, 4, 5, 2);
    b.plot('B', 1, 2).plot('B', 2, 2).plot('B', 3, 2);
    b.box('C', 1, 1, 4, 4);
    b.box('D', 1, 1, 3, 3);
    b.stack(1, 2, 3).stack(2, 2, 3);
  },
  // 3. Castle Keep
  (b) => {
    b.box('A', 1, 1, 6, 6, false);
    b.box('A', 2, 2, 4, 4);
    b.box('B', 1, 1, 5, 5);
    b.box('C', 1, 1, 4, 4);
    b.box('D', 1, 1, 3, 3);
    b.stack(1, 1, 4).stack(1, 6, 4);
  },
  // 4. Twin Citadel
  (b) => {
    b.box('A', 0, 1, 3, 6);
    b.line('A', 2, 3, 5, 3);
    b.box('B', 0, 1, 3, 5);
    b.box('C', 0, 1, 2, 4);
    b.box('D', 1, 1, 3, 3);
    b.stack(1, 1, 5);
  },
  // 5. Torii Gate
  (b) => {
    b.line('A', 0, 1, 7, 1);
    b.line('A', 1, 2, 6, 2);
    b.line('A', 2, 2, 2, 7);
    b.line('B', 1, 1, 5, 1);
    b.line('B', 2, 2, 2, 6);
    b.box('C', 1, 1, 4, 2);
    b.stack(2, 1, 3);
  },
  // 6. Cathedral
  (b) => {
    b.box('A', 1, 2, 6, 5);
    b.box('B', 1, 2, 5, 4);
    b.diamond('C', 2.5, 2.5, 2);
    b.box('D', 1, 1, 3, 3);
    b.stack(1, 1, 6);
  },
  // 7. Water Tower
  (b) => {
    b.box('A', 2, 1, 4, 4);
    b.line('A', 2, 5, 2, 7);
    b.line('A', 3, 5, 3, 7);
    b.box('B', 2, 1, 3, 3);
    b.box('C', 1, 1, 4, 4);
    b.box('D', 1, 1, 3, 3);
    b.stack(3, 2, 3);
  },
  // 8. Windmill
  (b) => {
    b.box('A', 2, 3, 4, 5);
    b.line('A', 0, 0, 7, 7);
    b.line('A', 0, 7, 7, 0);
    b.box('B', 2, 2, 3, 4);
    b.diamond('C', 2.5, 2.5, 2);
    b.plot('D', 2, 2);
  },
  // 9. Lighthouse
  (b) => {
    b.box('A', 1, 6, 6, 2);
    b.box('A', 2, 1, 4, 5);
    b.box('B', 1, 5, 5, 2);
    b.box('B', 2, 2, 3, 3);
    b.box('C', 1, 2, 4, 3);
    b.stack(3, 1, 5);
  },
  // 10. Triumphal Arch
  (b) => {
    b.box('A', 1, 1, 6, 2);
    b.box('A', 1, 3, 2, 5);
    b.box('B', 1, 1, 5, 2);
    b.box('B', 1, 3, 2, 4);
    b.box('C', 1, 1, 4, 2);
    b.stack(2, 1, 3);
  },
  // 11. Lotus Flower
  (b) => {
    b.ring('A', 3.5, 3.5, 2, 3.8);
    b.ring('B', 3, 3, 1.2, 2.8);
    b.diamond('C', 2.5, 2.5, 2);
    b.diamond('D', 2, 2, 1);
    b.plot('E', 1, 1).plot('E', 2, 1);
  },
  // 12. Sunflower
  (b) => {
    b.ring('A', 3.5, 3.5, 2.5, 3.8);
    b.box('B', 1, 1, 5, 5);
    b.ring('C', 2.5, 2.5, 1, 2.2);
    b.box('D', 1, 1, 3, 3);
    b.box('E', 1, 1, 2, 2);
  },
  // 13. Tulip
  (b) => {
    b.box('A', 2, 1, 4, 4);
    b.line('A', 3, 5, 3, 7);
    b.plot('A', 1, 6).plot('A', 2, 5);
    b.box('B', 2, 1, 3, 3);
    b.diamond('C', 2.5, 2, 1.5);
    b.box('D', 1, 1, 3, 2);
  },
  // 14. Four-Leaf Clover
  (b) => {
    b.box('A', 1, 1, 2, 2);
    b.box('A', 1, 4, 2, 2);
    b.box('B', 1, 1, 2, 2);
    b.box('B', 1, 4, 2, 2);
    b.box('C', 1, 1, 4, 4);
    b.diamond('D', 2, 2, 1.5);
    b.stack(3, 3, 3);
  },
  // 15. Pine Tree
  (b) => {
    b.line('A', 3, 0, 3, 6);
    b.line('A', 1, 4, 6, 4);
    b.line('A', 2, 2, 5, 2);
    b.box('A', 3, 6, 2, 2);
    b.box('B', 1, 2, 5, 4);
    b.diamond('C', 2.5, 2, 2);
    b.box('D', 1, 1, 3, 2);
    b.stack(3, 1, 3);
  },
  // 16. Bonsai
  (b) => {
    b.box('A', 1, 6, 6, 2);
    b.line('A', 3, 4, 3, 6);
    b.box('A', 0, 1, 8, 3);
    b.box('B', 1, 1, 5, 3);
    b.box('C', 1, 1, 4, 3);
    b.box('D', 1, 1, 3, 2);
  },
  // 17. Palm Oasis
  (b) => {
    b.box('A', 1, 6, 6, 2);
    b.line('A', 2, 3, 2, 6);
    b.line('A', 0, 1, 3, 3);
    b.box('B', 1, 1, 5, 3);
    b.diamond('C', 2.5, 2, 2);
    b.stack(2, 2, 3);
  },
  // 18. Giant Mushroom
  (b) => {
    b.box('A', 1, 1, 6, 3);
    b.box('A', 2, 4, 4, 4);
    b.box('B', 1, 1, 5, 2);
    b.box('B', 2, 3, 3, 3);
    b.diamond('C', 2.5, 1.5, 1.5);
    b.box('D', 1, 2, 3, 2);
  },
  // 19. Monarch Butterfly
  (b) => {
    b.box('A', 0, 1, 3, 3);
    b.box('A', 1, 4, 2, 3);
    b.line('A', 3, 1, 3, 6);
    b.box('B', 0, 1, 3, 3);
    b.box('B', 1, 4, 2, 2);
    b.diamond('C', 2.5, 2.5, 2);
    b.box('D', 1, 2, 3, 2);
    b.stack(3, 2, 2);
  },
  // 20. Dragonfly
  (b) => {
    b.line('A', 3, 0, 3, 7);
    b.line('A', 0, 2, 7, 2);
    b.line('A', 1, 4, 6, 4);
    b.box('B', 0, 2, 7, 1);
    b.box('B', 2, 1, 3, 5);
    b.diamond('C', 2.5, 2.5, 1.5);
    b.stack(3, 1, 3);
  },
  // 21. Wise Owl
  (b) => {
    b.box('A', 1, 1, 6, 6);
    b.plot('A', 1, 0).plot('A', 2, 0);
    b.box('B', 1, 1, 5, 5, false);
    b.box('C', 1, 1, 4, 4);
    b.diamond('D', 2, 2, 1.5);
    b.stack(2, 2, 3);
  },
  // 22. Soaring Eagle
  (b) => {
    b.line('A', 0, 1, 3, 4);
    b.line('A', 0, 2, 3, 5);
    b.box('A', 3, 2, 2, 5);
    b.box('B', 1, 2, 5, 3);
    b.diamond('C', 2.5, 2.5, 2);
    b.box('D', 1, 1, 3, 2);
  },
  // 23. Kitty Cat
  (b) => {
    b.plot('A', 1, 0).plot('A', 2, 1);
    b.box('A', 1, 2, 6, 5);
    b.box('B', 1, 1, 5, 5);
    b.diamond('C', 2.5, 2.5, 2);
    b.box('D', 1, 2, 3, 2);
    b.stack(2, 3, 2);
  },
  // 24. Clever Fox
  (b) => {
    b.plot('A', 1, 0).plot('A', 1, 1);
    b.line('A', 1, 2, 3, 6);
    b.box('A', 2, 2, 4, 3);
    b.box('B', 1, 1, 5, 4);
    b.diamond('C', 2.5, 2, 1.5);
    b.plot('D', 2, 2);
  },
  // 25. Royal Frog
  (b) => {
    b.plot('A', 1, 1).plot('A', 2, 1);
    b.box('A', 1, 2, 6, 5);
    b.box('B', 1, 1, 5, 4);
    b.diamond('C', 2.5, 2.5, 2);
    b.box('D', 1, 2, 3, 2);
    b.stack(1, 1, 3);
  },
  // 26. Swimming Fish
  (b) => {
    b.box('A', 2, 2, 4, 4);
    b.plot('A', 0, 1).plot('A', 1, 2).plot('A', 1, 4).plot('A', 0, 5);
    b.plot('A', 3, 1).plot('A', 4, 1);
    b.box('B', 1, 2, 5, 3);
    b.diamond('C', 2.5, 2.5, 1.5);
    b.stack(3, 3, 3);
  },
  // 27. Sea Turtle
  (b) => {
    b.diamond('A', 3.5, 3.5, 3);
    b.plot('A', 3, 0).plot('A', 4, 0);
    b.plot('A', 0, 2).plot('A', 1, 2);
    b.plot('A', 0, 5).plot('A', 1, 5);
    b.diamond('B', 3, 3, 2);
    b.diamond('C', 2.5, 2.5, 1.5);
    b.box('D', 1, 1, 3, 3);
  },
  // 28. Atlantic Crab
  (b) => {
    b.box('A', 2, 3, 4, 3);
    b.plot('A', 1, 1).plot('A', 1, 2);
    b.plot('A', 0, 2);
    b.line('A', 1, 5, 1, 7);
    b.box('B', 1, 2, 5, 3);
    b.diamond('C', 2.5, 2.5, 1.5);
    b.stack(1, 1, 3);
  },
  // 29. Honeybee
  (b) => {
    b.box('A', 3, 1, 2, 6);
    b.line('A', 0, 2, 3, 2);
    b.line('A', 0, 3, 3, 3);
    b.box('B', 1, 2, 5, 3);
    b.diamond('C', 2.5, 2.5, 1.5);
    b.box('D', 1, 1, 3, 2);
  },
  // 30. Golden Beetle
  (b) => {
    b.box('A', 2, 2, 4, 5);
    b.plot('A', 1, 0).plot('A', 2, 1);
    b.line('A', 0, 3, 2, 3);
    b.line('A', 0, 5, 2, 5);
    b.box('B', 1, 2, 5, 4);
    b.diamond('C', 2.5, 2.5, 1.5);
    b.stack(3, 3, 3);
  },
  // 31. Giant Panda
  (b) => {
    b.plot('A', 1, 0).plot('A', 2, 1);
    b.box('A', 1, 2, 6, 5);
    b.box('B', 1, 1, 5, 5);
    b.diamond('C', 2.5, 2.5, 2);
    b.plot('C', 1, 1);
    b.box('D', 1, 2, 3, 2);
  },
  // 32. Coffee Mug
  (b) => {
    b.box('A', 1, 7, 6, 1);
    b.box('A', 2, 2, 4, 5);
    b.plot('A', 6, 3).plot('A', 6, 4);
    b.line('A', 2, 0, 3, 1);
    b.box('B', 1, 2, 4, 4);
    b.diamond('C', 2, 2, 1.5);
    b.box('D', 1, 1, 3, 2);
  },
  // 33. Moka Pot
  (b) => {
    b.box('A', 2, 5, 4, 3);
    b.box('A', 3, 4, 2, 1);
    b.box('A', 1, 1, 6, 3);
    b.plot('A', 0, 2);
    b.plot('A', 7, 2);
    b.box('B', 1, 1, 5, 4);
    b.box('C', 1, 1, 4, 3);
    b.plot('D', 2, 1);
  },
  // 34. French Press
  (b) => {
    b.box('A', 2, 2, 4, 5);
    b.line('A', 3, 0, 3, 2);
    b.plot('A', 3, 0).plot('A', 4, 0);
    b.plot('A', 6, 3).plot('A', 6, 4);
    b.box('B', 1, 2, 4, 4);
    b.diamond('C', 2, 2.5, 1.5);
    b.stack(3, 0, 3);
  },
  // 35. Teapot
  (b) => {
    b.box('A', 2, 2, 4, 5);
    b.line('A', 0, 2, 2, 4);
    b.plot('A', 6, 2).plot('A', 7, 3).plot('A', 6, 4);
    b.plot('A', 3, 1).plot('A', 4, 1);
    b.box('B', 1, 2, 5, 4);
    b.diamond('C', 2.5, 2.5, 2);
    b.box('D', 1, 1, 3, 2);
  },
  // 36. Wedding Cake
  (b) => {
    b.box('A', 0, 5, 8, 3);
    b.box('A', 1, 3, 6, 2);
    b.box('A', 2, 1, 4, 2);
    b.box('B', 1, 3, 5, 3);
    b.box('B', 2, 1, 3, 2);
    b.box('C', 1, 1, 4, 3);
    b.diamond('D', 2, 1.5, 1);
    b.stack(3, 1, 3);
  },
  // 37. Sweet Cupcake
  (b) => {
    b.box('A', 2, 4, 4, 4);
    b.box('A', 1, 1, 6, 3);
    b.plot('A', 3, 0).plot('A', 4, 0);
    b.box('B', 1, 2, 5, 4);
    b.diamond('C', 2.5, 2, 2);
    b.box('D', 1, 1, 3, 2);
  },
  // 38. Ice Cream Sundae
  (b) => {
    b.box('A', 2, 6, 4, 2);
    b.box('A', 1, 3, 6, 3);
    b.ring('A', 3.5, 2, 1, 2);
    b.box('A', 2, 1, 4, 2);
    b.box('B', 1, 2, 5, 4);
    b.diamond('C', 2.5, 2, 1.5);
    b.stack(3, 1, 4);
  },
  // 39. Croissant
  (b) => {
    b.line('A', 0, 5, 3, 2);
    b.line('A', 0, 4, 3, 1);
    b.box('A', 2, 1, 4, 3);
    b.box('B', 1, 2, 5, 3);
    b.diamond('C', 2.5, 2, 1.5);
    b.box('D', 1, 1, 3, 2);
  },
  // 40. Glazed Donut
  (b) => {
    b.ring('A', 3.5, 3.5, 1.8, 3.8);
    b.ring('B', 3, 3, 1.4, 2.8);
    b.diamond('C', 2.5, 2.5, 2, false);
    b.box('D', 1, 1, 3, 3, false);
    b.stack(1, 1, 3).stack(1, 6, 3);
  },
  // 41. Deluxe Burger
  (b) => {
    b.box('A', 1, 1, 6, 2);
    b.box('A', 0, 3, 8, 1);
    b.box('A', 1, 4, 6, 2);
    b.box('A', 1, 6, 6, 2);
    b.box('B', 1, 1, 5, 5);
    b.box('C', 1, 1, 4, 4);
    b.diamond('D', 2, 2, 1.5);
  },
  // 42. Chef Toque
  (b) => {
    b.box('A', 2, 5, 4, 3);
    b.box('A', 1, 1, 6, 4);
    b.plot('A', 1, 0).plot('A', 3, 0);
    b.box('B', 1, 2, 5, 4);
    b.diamond('C', 2.5, 2, 2);
    b.box('D', 1, 1, 3, 2);
  },
  // 43. Imperial Crown
  (b) => {
    b.box('A', 1, 6, 6, 2);
    b.plot('A', 1, 2).plot('A', 3, 1);
    b.box('A', 2, 3, 4, 3);
    b.box('B', 1, 2, 5, 4);
    b.diamond('C', 2.5, 2.5, 2);
    b.stack(1, 2, 3).stack(3, 1, 4);
  },
  // 44. Sweetheart
  (b) => {
    b.plot('A', 1, 1).plot('A', 2, 0).plot('A', 3, 1);
    b.box('A', 1, 2, 6, 3);
    b.line('A', 1, 4, 3, 7);
    b.box('B', 1, 1, 5, 4);
    b.diamond('C', 2.5, 2.5, 2);
    b.box('D', 1, 1, 3, 2);
  },
  // 45. Entwined Hearts
  (b) => {
    b.diamond('A', 2.5, 2.5, 2.5);
    b.diamond('A', 4.5, 4.5, 2.5);
    b.box('B', 1, 1, 5, 5);
    b.diamond('C', 2.5, 2.5, 2);
    b.box('D', 1, 1, 3, 3);
  },
  // 46. Brilliant Diamond
  (b) => {
    b.line('A', 1, 2, 6, 2);
    b.line('A', 0, 3, 7, 3);
    b.line('A', 0, 3, 3, 7);
    b.box('B', 1, 2, 5, 3);
    b.diamond('C', 2.5, 2.5, 2);
    b.box('D', 1, 1, 3, 2);
  },
  // 47. Guiding Star
  (b) => {
    b.diamond('A', 3.5, 3.5, 3.5);
    b.line('A', 3, 0, 3, 7);
    b.line('A', 0, 3, 7, 3);
    b.diamond('B', 3, 3, 2.5);
    b.diamond('C', 2.5, 2.5, 1.5);
    b.plot('D', 2, 2);
    b.stack(3, 3, 4);
  },
  // 48. Frost Snowflake
  (b) => {
    b.line('A', 3, 0, 3, 7);
    b.line('A', 0, 3, 7, 3);
    b.line('A', 1, 1, 6, 6);
    b.line('A', 1, 6, 6, 1);
    b.ring('B', 3, 3, 1, 2.5);
    b.diamond('C', 2.5, 2.5, 1.5);
    b.stack(1, 1, 3);
  },
  // 49. Antique Key
  (b) => {
    b.ring('A', 3.5, 1.5, 1, 2);
    b.line('A', 3, 3, 3, 7);
    b.plot('A', 4, 6).plot('A', 5, 6).plot('A', 5, 7);
    b.box('B', 2, 1, 3, 5);
    b.diamond('C', 2.5, 2, 1.5);
    b.box('D', 1, 1, 3, 2);
  },
  // 50. Brass Padlock
  (b) => {
    b.box('A', 2, 0, 4, 3, false);
    b.box('A', 1, 3, 6, 5);
    b.box('B', 1, 2, 5, 4);
    b.diamond('C', 2.5, 2.5, 2);
    b.box('D', 1, 2, 3, 2);
  },
  // 51. Lucky Horseshoe
  (b) => {
    b.box('A', 1, 1, 6, 6, false);
    b.plot('A', 1, 0).plot('A', 2, 0);
    b.box('B', 1, 1, 5, 5, false);
    b.box('C', 1, 1, 4, 4, false);
    b.stack(1, 1, 4);
  },
  // 52. Ship Anchor
  (b) => {
    b.line('A', 3, 0, 3, 7);
    b.line('A', 1, 2, 6, 2);
    b.line('A', 1, 6, 6, 6);
    b.plot('A', 1, 5).plot('A', 2, 7);
    b.box('B', 1, 2, 5, 4);
    b.diamond('C', 2.5, 2.5, 2);
    b.plot('D', 2, 2);
  },
  // 53. Captain's Helm
  (b) => {
    b.ring('A', 3.5, 3.5, 1.5, 3);
    b.line('A', 3, 0, 3, 7);
    b.line('A', 0, 3, 7, 3);
    b.ring('B', 3, 3, 1, 2);
    b.diamond('C', 2.5, 2.5, 1.5);
    b.plot('D', 2, 2);
  },
  // 54. Compass Rose
  (b) => {
    b.box('A', 0, 0, 8, 8, false);
    b.diamond('A', 3.5, 3.5, 3.5);
    b.ring('B', 3, 3, 1.5, 2.5);
    b.diamond('C', 2.5, 2.5, 2);
    b.diamond('D', 2, 2, 1);
    b.stack(3, 3, 2);
  },
  // 55. Classic Hourglass
  (b) => {
    b.line('A', 1, 1, 6, 1);
    b.line('A', 1, 6, 6, 6);
    b.line('A', 1, 1, 3, 4);
    b.line('A', 1, 6, 3, 4);
    b.box('B', 1, 1, 5, 5);
    b.diamond('C', 2.5, 2.5, 2);
    b.plot('D', 2, 2);
  },
  // 56. Celtic Knot
  (b) => {
    b.ring('A', 2.5, 2.5, 1, 2.5);
    b.ring('A', 4.5, 4.5, 1, 2.5);
    b.box('B', 1, 1, 5, 5);
    b.diamond('C', 2.5, 2.5, 2);
    b.box('D', 1, 1, 3, 3);
  },
  // 57. Maltese Cross
  (b) => {
    b.diamond('A', 3.5, 3.5, 3.5);
    b.plot('A', 3, 3, 0).plot('A', 4, 3, 0).plot('A', 3, 4, 0).plot('A', 4, 4, 0);
    b.box('B', 1, 1, 5, 5);
    b.diamond('C', 2.5, 2.5, 2);
    b.box('D', 1, 1, 3, 3);
  },
  // 58. Templar Cross
  (b) => {
    b.box('A', 2, 0, 4, 8);
    b.box('A', 0, 2, 8, 4);
    b.box('B', 1, 1, 5, 5);
    b.diamond('C', 2.5, 2.5, 2);
    b.box('D', 1, 1, 3, 3);
    b.stack(3, 3, 3);
  },
  // 59. Yin-Yang Swirl
  (b) => {
    b.ring('A', 3.5, 3.5, 1, 3.5);
    b.box('B', 1, 1, 5, 5);
    b.diamond('C', 2.5, 2.5, 2);
    b.box('D', 1, 1, 3, 3);
  },
  // 60. Knight Shield
  (b) => {
    b.box('A', 1, 1, 6, 4);
    b.line('A', 1, 4, 3, 7);
    b.box('B', 1, 1, 5, 4);
    b.diamond('C', 2.5, 2, 2);
    b.box('D', 1, 1, 3, 2);
    b.stack(3, 2, 3);
  },
  // 61. Fleur-de-lis
  (b) => {
    b.line('A', 3, 0, 3, 6);
    b.line('A', 1, 2, 2, 5);
    b.line('A', 1, 5, 6, 5);
    b.box('B', 1, 1, 5, 4);
    b.diamond('C', 2.5, 2, 2);
    b.box('D', 1, 1, 3, 2);
  },
  // 62. Satin Bow
  (b) => {
    b.diamond('A', 1.5, 3.5, 2);
    b.diamond('A', 5.5, 3.5, 2);
    b.diamond('A', 3.5, 3.5, 1);
    b.line('A', 2, 5, 1, 7);
    b.box('B', 1, 2, 5, 3);
    b.diamond('C', 2.5, 2.5, 1.5);
    b.stack(3, 3, 3);
  },
  // 63. Golden Harp
  (b) => {
    b.line('A', 1, 1, 1, 6);
    b.line('A', 1, 1, 6, 2);
    b.line('A', 1, 6, 6, 5);
    b.box('A', 2, 2, 4, 4, false);
    b.box('B', 1, 1, 5, 4);
    b.diamond('C', 2.5, 2, 1.5);
  },
  // 64. Treble Clef
  (b) => {
    b.line('A', 3, 0, 3, 7);
    b.ring('A', 3.5, 3.5, 1, 2.2);
    b.plot('A', 2, 7);
    b.box('B', 1, 1, 5, 5);
    b.diamond('C', 2.5, 2.5, 2);
  },
  // 65. Liberty Bell
  (b) => {
    b.box('A', 2, 1, 4, 2);
    b.box('A', 1, 3, 6, 3);
    b.box('A', 0, 6, 8, 2);
    b.box('B', 1, 2, 5, 4);
    b.diamond('C', 2.5, 2.5, 2);
    b.box('D', 1, 2, 3, 2);
  },
  // 66. Magic Wand
  (b) => {
    b.diamond('A', 3.5, 1.5, 1.8);
    b.line('A', 3, 3, 3, 7);
    b.box('B', 2, 1, 3, 5);
    b.diamond('C', 2.5, 1.5, 1.5);
    b.stack(3, 1, 4);
  },
  // 67. Wizard Hat
  (b) => {
    b.box('A', 0, 6, 8, 2);
    b.line('A', 0, 6, 3, 1);
    b.box('A', 2, 2, 4, 4);
    b.box('B', 1, 3, 5, 3);
    b.diamond('C', 2.5, 2, 2);
    b.plot('D', 2, 1);
  },
  // 68. Cosmic Rocket
  (b) => {
    b.box('A', 2, 2, 4, 4);
    b.line('A', 2, 2, 3, 0);
    b.plot('A', 1, 5).plot('A', 0, 6);
    b.box('B', 1, 1, 5, 4);
    b.diamond('C', 2.5, 2, 2);
    b.stack(3, 1, 3);
  },
  // 69. Propeller Plane
  (b) => {
    b.line('A', 3, 0, 3, 7);
    b.line('A', 0, 3, 7, 3);
    b.line('A', 1, 6, 6, 6);
    b.box('B', 1, 2, 5, 3);
    b.diamond('C', 2.5, 2.5, 1.5);
  },
  // 70. Hot Air Balloon
  (b) => {
    b.box('A', 1, 0, 6, 5);
    b.box('A', 2, 6, 4, 2);
    b.box('B', 1, 1, 5, 4);
    b.diamond('C', 2.5, 2, 2);
    b.box('D', 1, 1, 3, 2);
  },
  // 71. Sailing Sloop
  (b) => {
    b.box('A', 0, 6, 8, 2);
    b.line('A', 3, 1, 3, 6);
    b.line('A', 0, 5, 3, 2);
    b.box('B', 1, 3, 5, 3);
    b.diamond('C', 2.5, 2.5, 1.5);
  },
  // 72. Ancient Ziggurat
  (b) => {
    b.box('A', 0, 0, 8, 8);
    b.box('B', 0, 0, 7, 7);
    b.box('C', 0, 0, 6, 6);
    b.box('D', 0, 0, 5, 5);
    b.box('E', 0, 0, 4, 4);
    b.stack(3, 3, 2);
  },
  // 73. Mayan Pyramid
  (b) => {
    b.box('A', 1, 1, 6, 6);
    b.line('A', 3, 0, 3, 7);
    b.box('B', 1, 1, 5, 5);
    b.box('C', 1, 1, 4, 4);
    b.box('D', 1, 1, 3, 3);
    b.plot('E', 1, 1);
  },
  // 74. Terraced Steps
  (b) => {
    b.box('A', 0, 4, 8, 4);
    b.box('B', 0, 3, 7, 4);
    b.box('C', 0, 2, 6, 4);
    b.box('D', 0, 1, 5, 4);
    b.box('E', 0, 0, 4, 4);
  },
  // 75. Concentric Fortress
  (b) => {
    b.box('A', 0, 0, 8, 8, false);
    b.box('B', 1, 1, 5, 5, false);
    b.box('C', 1, 1, 4, 4);
    b.box('D', 1, 1, 3, 3);
    b.stack(2, 2, 4);
  },
  // 76. Roman Colosseum
  (b) => {
    b.ring('A', 3.5, 3.5, 2.5, 3.8);
    b.ring('B', 3, 3, 1.8, 3.0);
    b.ring('C', 2.5, 2.5, 1.2, 2.2);
    b.diamond('D', 2, 2, 1);
  },
  // 77. Classical Maze
  (b) => {
    b.box('A', 0, 0, 8, 8, false);
    b.box('A', 2, 2, 4, 4, false);
    b.box('B', 1, 1, 5, 5);
    b.box('C', 1, 1, 4, 4);
    b.diamond('D', 2, 2, 1.5);
  },
  // 78. Diamond Matrix
  (b) => {
    b.box('A', 0, 0, 8, 8, false);
    b.diamond('A', 3.5, 3.5, 3.5, false);
    b.diamond('B', 3, 3, 2.5, false);
    b.diamond('C', 2.5, 2.5, 2);
    b.diamond('D', 2, 2, 1);
  },
  // 79. Chess King
  (b) => {
    b.box('A', 1, 6, 6, 2);
    b.box('A', 2, 2, 4, 4);
    b.plot('A', 3, 0).plot('A', 4, 0);
    b.box('B', 1, 2, 5, 4);
    b.diamond('C', 2.5, 2.5, 2);
    b.stack(3, 1, 4);
  },
  // 80. Chess Queen
  (b) => {
    b.box('A', 1, 6, 6, 2);
    b.box('A', 2, 2, 4, 4);
    b.plot('A', 1, 1).plot('A', 3, 0);
    b.box('B', 1, 1, 5, 5);
    b.diamond('C', 2.5, 2.5, 2);
    b.box('D', 1, 1, 3, 3);
  },
  // 81. Chess Rook
  (b) => {
    b.box('A', 1, 6, 6, 2);
    b.box('A', 2, 2, 4, 4);
    b.plot('A', 1, 1).plot('A', 3, 1);
    b.box('B', 1, 2, 5, 4);
    b.box('C', 1, 1, 4, 4);
    b.stack(2, 2, 3);
  },
  // 82. Chess Knight
  (b) => {
    b.box('A', 1, 6, 6, 2);
    b.box('A', 2, 2, 4, 4);
    b.plot('A', 1, 1).plot('A', 2, 1);
    b.box('B', 1, 2, 5, 4);
    b.diamond('C', 2.5, 2.5, 2);
    b.box('D', 1, 1, 3, 3);
  },
  // 83. Radiant Sunburst
  (b) => {
    b.ring('A', 3.5, 3.5, 1, 3.5);
    b.line('A', 0, 3, 7, 3);
    b.line('A', 3, 0, 3, 7);
    b.ring('B', 3, 3, 1, 2.5);
    b.diamond('C', 2.5, 2.5, 2);
    b.box('D', 1, 1, 3, 3);
    b.stack(3, 3, 3);
  },
  // 84. Crescent & Star
  (b) => {
    b.ring('A', 3.5, 3.5, 2, 3.8);
    b.diamond('A', 3.5, 3.5, 1.5);
    b.box('B', 1, 1, 5, 5);
    b.diamond('C', 2.5, 2.5, 2);
    b.box('D', 1, 1, 3, 3);
  },
  // 85. Sacred Scarab
  (b) => {
    b.ring('A', 3.5, 1, 1, 1.8);
    b.diamond('A', 3.5, 4.5, 3);
    b.box('B', 1, 1, 5, 5);
    b.diamond('C', 2.5, 2.5, 2);
    b.stack(3, 1, 4);
  },
  // 86. Rising Phoenix
  (b) => {
    b.line('A', 0, 1, 3, 4);
    b.line('A', 0, 3, 3, 6);
    b.box('A', 3, 2, 2, 5);
    b.box('B', 1, 1, 5, 4);
    b.diamond('C', 2.5, 2, 2);
    b.stack(3, 1, 3);
  },
  // 87. Dragon Crest
  (b) => {
    b.plot('A', 1, 0).plot('A', 2, 1);
    b.box('A', 1, 2, 6, 4);
    b.line('A', 1, 6, 6, 6);
    b.box('B', 1, 1, 5, 5);
    b.diamond('C', 2.5, 2.5, 2);
    b.box('D', 1, 1, 3, 3);
  },
  // 88. Royal Peacock
  (b) => {
    b.ring('A', 3.5, 3.5, 2, 3.8);
    b.line('A', 3, 2, 3, 6);
    b.box('B', 1, 1, 5, 5);
    b.diamond('C', 2.5, 2.5, 2);
    b.box('D', 1, 1, 3, 3);
  },
  // 89. Graceful Swan
  (b) => {
    b.box('A', 1, 3, 6, 4);
    b.line('A', 3, 0, 3, 4);
    b.plot('A', 2, 0);
    b.box('B', 1, 2, 5, 4);
    b.diamond('C', 2.5, 2.5, 2);
    b.box('D', 1, 1, 3, 3);
  },
  // 90. Butterfly Garden
  (b) => {
    b.box('A', 0, 0, 8, 8, false);
    b.diamond('A', 3.5, 3.5, 2);
    b.box('B', 1, 1, 5, 5);
    b.diamond('C', 2.5, 2.5, 2);
    b.box('D', 1, 1, 3, 3);
  },
  // 91. High Tea Service
  (b) => {
    b.box('A', 2, 2, 4, 4);
    b.box('A', 0, 4, 2, 2);
    b.box('A', 6, 4, 2, 2);
    b.box('B', 1, 2, 5, 4);
    b.diamond('C', 2.5, 2.5, 2);
    b.stack(3, 2, 3);
  },
  // 92. Bistro Table
  (b) => {
    b.box('A', 1, 0, 6, 2);
    b.line('A', 3, 2, 3, 5);
    b.box('A', 2, 4, 4, 1);
    b.box('A', 1, 5, 2, 2);
    b.box('A', 5, 5, 2, 2);
    b.box('B', 1, 1, 5, 4);
    b.diamond('C', 2.5, 2, 2);
  },
  // 93. Coffee Bean Emblem
  (b) => {
    b.ring('A', 3.5, 3.5, 2, 3.8);
    b.line('A', 2, 2, 5, 5);
    b.box('B', 1, 1, 5, 5);
    b.diamond('C', 2.5, 2.5, 2);
    b.stack(3, 3, 3);
  },
  // 94. Sundial Dial
  (b) => {
    b.ring('A', 3.5, 3.5, 2, 3.8);
    b.line('A', 3, 1, 5, 5);
    b.box('B', 1, 1, 5, 5);
    b.diamond('C', 2.5, 2.5, 2);
    b.box('D', 1, 1, 3, 3);
  },
  // 95. Kaleidoscope Rose
  (b) => {
    b.diamond('A', 3.5, 3.5, 3.5);
    b.box('A', 1, 1, 6, 6, false);
    b.diamond('B', 3, 3, 2.5);
    b.diamond('C', 2.5, 2.5, 1.5);
    b.box('D', 1, 1, 3, 3);
    b.stack(3, 3, 3);
  },
  // 96. Royal Scepter
  (b) => {
    b.diamond('A', 3.5, 1.5, 1.8);
    b.line('A', 3, 3, 3, 7);
    b.box('B', 1, 1, 5, 5);
    b.diamond('C', 2.5, 2.5, 2);
    b.stack(3, 1, 4);
  },
  // 97. Golden Chalice
  (b) => {
    b.box('A', 1, 1, 6, 3);
    b.line('A', 3, 4, 3, 6);
    b.box('A', 1, 6, 6, 2);
    b.box('B', 1, 1, 5, 4);
    b.diamond('C', 2.5, 2, 2);
    b.stack(3, 2, 3);
  },
  // 98. Diamond Tiara
  (b) => {
    b.box('A', 0, 6, 8, 2);
    b.plot('A', 0, 4).plot('A', 2, 2).plot('A', 3, 0);
    b.box('B', 1, 2, 5, 4);
    b.diamond('C', 2.5, 2, 2);
    b.stack(3, 0, 4);
  },
  // 99. Genie's Lamp
  (b) => {
    b.box('A', 1, 3, 6, 4);
    b.line('A', 0, 2, 2, 4);
    b.plot('A', 6, 1).plot('A', 7, 2).plot('A', 6, 3);
    b.box('B', 1, 2, 5, 4);
    b.diamond('C', 2.5, 2.5, 2);
    b.stack(2, 2, 3);
  },
  // 100. Grand Finale: The Cafe Manor
  (b) => {
    b.box('A', 0, 0, 8, 8);
    b.box('B', 0, 0, 7, 7);
    b.box('C', 0, 0, 6, 6);
    b.box('D', 0, 0, 5, 5);
    b.box('E', 0, 0, 4, 4);
    b.stack(1, 1, 4).stack(1, 6, 4).stack(3, 3, 5);
  },
];

console.log('Generating 100 new level layouts...');
const newLevels = [];
for (let i = 0; i < generators.length; i++) {
  const b = new LevelBuilder(51 + i, 'Level_' + (52 + i));
  generators[i](b);
  const data = b.toData();
  newLevels.push(data);
}

module.exports = { newLevels };
