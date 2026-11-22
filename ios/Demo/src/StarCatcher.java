import javax.microedition.lcdui.*;
import javax.microedition.midlet.*;

/** Catch the falling stars with the paddle; miss three and the game is over. */
public class StarCatcher extends MIDlet implements CommandListener {
    private Game game;

    protected void startApp() {
        if (game == null) {
            game = new Game();
            game.addCommand(new Command("Exit", Command.EXIT, 1));
            game.setCommandListener(this);
        }
        Display.getDisplay(this).setCurrent(game);
        game.start();
    }

    protected void pauseApp() { if (game != null) game.stop(); }

    protected void destroyApp(boolean unconditional) {
        if (game != null) game.stop();
    }

    public void commandAction(Command c, Displayable d) {
        destroyApp(true);
        notifyDestroyed();
    }

    static class Game extends Canvas implements Runnable {
        private static final int N = 5;
        private final int[] sx = new int[N], sy = new int[N], sv = new int[N];
        private int px, move, score, lives, best, tick;
        private boolean over, running, title = true;
        private long seed = 12345;
        private Thread thread;

        Game() { reset(); }

        private int rnd(int n) {
            seed = (seed * 1103515245L + 12345L) & 0x7fffffffL;
            return (int) ((seed >> 8) % n);
        }

        private void reset() {
            int w = getWidth();
            px = w / 2; move = 0; score = 0; lives = 3; tick = 0; over = false;
            for (int i = 0; i < N; i++) respawn(i, -i * 40);
        }

        private void respawn(int i, int y) {
            int w = getWidth() > 0 ? getWidth() : 176;
            sx[i] = 8 + rnd(w - 16);
            sy[i] = y;
            sv[i] = 2 + rnd(2) + score / 15;
        }

        void start() {
            if (running) return;
            running = true;
            thread = new Thread(this);
            thread.start();
        }

        void stop() { running = false; }

        public void run() {
            while (running) {
                step();
                repaint();
                serviceRepaints();
                try { Thread.sleep(40); } catch (InterruptedException e) { }
            }
        }

        private void step() {
            tick++;
            if (title || over) return;
            int w = getWidth(), h = getHeight();
            int pw = 36, py = h - 14;
            px += move * 5;
            if (px < pw / 2) px = pw / 2;
            if (px > w - pw / 2) px = w - pw / 2;
            for (int i = 0; i < N; i++) {
                sy[i] += sv[i];
                if (sy[i] >= py - 6 && sy[i] <= py + 4 && sx[i] >= px - pw / 2 - 4 && sx[i] <= px + pw / 2 + 4) {
                    score++;
                    respawn(i, -10);
                } else if (sy[i] > h) {
                    lives--;
                    respawn(i, -10);
                    if (lives <= 0) {
                        over = true;
                        if (score > best) best = score;
                    }
                }
            }
        }

        protected void paint(Graphics g) {
            int w = getWidth(), h = getHeight();
            if (title) {
                g.setColor(0x10183c);
                g.fillRect(0, 0, w, h);
                g.setColor(0xffe040);
                g.drawString("Star Catcher", w / 2, h / 4, Graphics.TOP | Graphics.HCENTER);
                g.setColor(0xffffff);
                g.drawString("Catch the falling stars", w / 2, h / 4 + 22, Graphics.TOP | Graphics.HCENTER);
                g.drawString("Created for GenJ2", w / 2, h / 2 + 10, Graphics.TOP | Graphics.HCENTER);
                g.drawString("by Yoshi Sugawara", w / 2, h / 2 + 28, Graphics.TOP | Graphics.HCENTER);
                g.drawString("2026", w / 2, h / 2 + 46, Graphics.TOP | Graphics.HCENTER);
                if ((tick / 12) % 2 == 0) {
                    g.setColor(0xffe040);
                    g.drawString("Press OK to start", w / 2, h - 50, Graphics.TOP | Graphics.HCENTER);
                }
                return;
            }
            g.setColor(0x10183c);
            g.fillRect(0, 0, w, h);
            g.setColor(0x3a4a8c);
            for (int i = 0; i < 24; i++) g.fillRect((i * 53) % w, (i * 97 + tick / 3) % h, 1, 1);
            g.setColor(0xffe040);
            for (int i = 0; i < N; i++) {
                g.fillArc(sx[i] - 5, sy[i] - 5, 11, 11, 0, 360);
            }
            int py = h - 14;
            g.setColor(0x40e0ff);
            g.fillRect(px - 18, py, 36, 8);
            g.setColor(0xffffff);
            g.drawString("Score " + score, 4, 2, Graphics.TOP | Graphics.LEFT);
            g.drawString("Lives " + lives, w - 4, 2, Graphics.TOP | Graphics.RIGHT);
            if (over) {
                g.setColor(0xff6060);
                g.drawString("GAME OVER", w / 2, h / 2 - 20, Graphics.TOP | Graphics.HCENTER);
                g.setColor(0xffffff);
                g.drawString("Best " + best, w / 2, h / 2, Graphics.TOP | Graphics.HCENTER);
                g.drawString("Press OK to play", w / 2, h / 2 + 20, Graphics.TOP | Graphics.HCENTER);
            }
        }

        private int dir(int key) {
            int a = getGameAction(key);
            if (a == LEFT || key == Canvas.KEY_NUM4) return -1;
            if (a == RIGHT || key == Canvas.KEY_NUM6) return 1;
            return 0;
        }

        protected void keyPressed(int key) {
            int d = dir(key);
            if (d != 0) move = d;
            else if (getGameAction(key) == FIRE || key == Canvas.KEY_NUM5) {
                if (title) { title = false; reset(); }
                else if (over) reset();
            }
        }

        protected void keyRepeated(int key) { keyPressed(key); }

        protected void keyReleased(int key) {
            if (dir(key) == move) move = 0;
        }
    }
}
