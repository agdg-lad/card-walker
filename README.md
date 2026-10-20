# card-walker

Score attack map traversal game with playing cards.

You start with a hand of 3 cards + a joker.
You draw a card and must choose if you want to discard it or walk it. You earn points by walking on cards.

Walk rules:

>same suite + previous/next rank
>same rank + previous/next suite
>joker can walk to any card

ie A2 -> [A3, AA, B2, D2, joker]
ie joker -> [all cards]

The game ends once there is no more cards on the deck.

Made using love2d + opencode + Muse Spark 1.3 Free. Total 99 messages.

## Post-mortem

I want to learn a workflow on how to create games using agentic AI. I remember having this idea on my mind since Balatro went out and we all went insane on /agdg/ to create card games, but never really tried because I was sure it wasn't good enough to even try. But now we can create shit prototypes like this "easily" so I decided to give a try.

It took me 2 days to finish the game. I started with a basic core loop that I wrote some time ago:

```md
Create this game using love2d. No external tools.


Card game. You must "walk" through all cards.

- containers
  - deck
  - hand
  - pile
  - trash
- shuffle deck
- player starts with the first card on hand
- shuffle deck
- player draw card
  - if impossible to walk
    - player loses
  - if card is the next/previous/equal of some card on hand and player wants to walk
    - discard that card on hand and hold the new card
    - shuffle deck
  - if not
    - send card to pile
    - if card is the last on deck
      - hold card
    - send pile to deck
    - shuffle deck
    - restart

```

After this I started to fine tune the mechanics and once it played good enough I started to improve the visuals.
29 messages later and this was the result ![](https://arch-img.b4k.dev/vg/1791873906494.mp4)

The main game was done but I went to improve the visuals further. Trying to mimic the style of Playdate games.

This was the final result after 99 messages: ![](https://arch-img.b4k.dev/vg/1791928115719.mp4)

### Lessons learned

- You can create games with the free models, if you do it the traditional way of iterating over your idea;
- AI models take prompts too literally. If you say something in some abscract way, it will use that concept everywhere, in variable names, in comments, in-game text, etc;
- Pseudocode works great, even simple ones;
- Fine tunning is almost impossible, at least using a code-only framework. Next time I'll for sure ask it to create an editable resource and expose in-game variables to finetune them. This could be easily done using godot/unity via the editor;
- I must find some "typed" way to create assets via text;
- Every time I asked it to create something by itself it was horrible. If I wanted a particular layout I had to write pseudocode or send a picture.
