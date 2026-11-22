import javax.microedition.lcdui.*;
import javax.microedition.midlet.*;

/** Auto-firing space shooter: slide left and right and survive waves that fly in different patterns. */
public class VoidWave extends MIDlet implements CommandListener {
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

    protected void destroyApp(boolean unconditional) { if (game != null) game.stop(); }

    public void commandAction(Command c, Displayable d) {
        destroyApp(true);
        notifyDestroyed();
    }

    static class Game extends Canvas implements Runnable {
        // sin(2*pi*i/32) * 100
        private static final int[] SIN = {0, 20, 38, 56, 71, 83, 92, 98, 100, 98, 92, 83, 71, 56, 38, 20,
                                          0, -20, -38, -56, -71, -83, -92, -98, -100, -98, -92, -83, -71, -56, -38, -20};
        private static final int ME = 16, MB = 12, MEB = 14, MX = 8;

        // enemies
        private final int[] ex = new int[ME], ey = new int[ME], ehp = new int[ME], eage = new int[ME];
        private final int[] ei = new int[ME], est = new int[ME];
        private final boolean[] ealive = new boolean[ME];
        // bullets
        private final int[] bx = new int[MB], by = new int[MB];
        private final boolean[] ba = new boolean[MB];
        private final int[] ebx = new int[MEB], eby = new int[MEB];
        private final boolean[] eba = new boolean[MEB];
        // explosions
        private final int[] xx = new int[MX], xy = new int[MX], xa = new int[MX];

        private int px, move, score, best, lives, wave, pattern, count, tick, fire, hurt, banner, kills, bonus;
        private boolean over, running, title = true;
        private long seed = 777;

        Game() { reset(); }

        private int rnd(int n) {
            seed = (seed * 1103515245L + 12345L) & 0x7fffffffL;
            return (int) ((seed >> 8) % n);
        }

        private int sin(int i) { return SIN[((i % 32) + 32) % 32]; }
        private int cos(int i) { return sin(i + 8); }
        private int abs(int v) { return v < 0 ? -v : v; }

        private void reset() {
            int w = getWidth() > 0 ? getWidth() : 240;
            px = w / 2; move = 0; score = 0; bonus = 0; lives = 3; wave = 0; tick = 0; fire = 0; hurt = 0;
            over = false;
            for (int i = 0; i < ME; i++) ealive[i] = false;
            for (int i = 0; i < MB; i++) ba[i] = false;
            for (int i = 0; i < MEB; i++) eba[i] = false;
            for (int i = 0; i < MX; i++) xa[i] = 99;
            nextWave();
        }

        private void nextWave() {
            wave++;
            kills = 0;
            pattern = (wave - 1) % 6;
            count = 6 + (wave - 1) / 6 * 2;
            if (count > ME) count = ME;
            if (pattern == 1 && count % 2 == 0) count++;
            if (count > ME) count = ME;
            banner = 40;
            for (int i = 0; i < count; i++) {
                ealive[i] = true;
                ei[i] = i;
                eage[i] = 0;
                ehp[i] = 1 + (wave > 6 && i % 3 == 0 ? 1 : 0) + (wave > 12 && i % 2 == 0 ? 1 : 0);
                int gap = pattern == 4 ? 6 : (pattern == 0 || pattern == 1) ? 0 : 10;
                est[i] = tick + banner + i * gap;
                ex[i] = -50; ey[i] = -50;
            }
        }

        /** Where enemy i of the current pattern is a ticks after it appears. */
        private void place(int k) {
            int w = getWidth(), a = eage[k], i = ei[k], n = count;
            int x, y;
            if (pattern == 0) {          // a row that sways while it descends
                x = w * (i + 1) / (n + 1) + 14 * sin(a / 4) / 100;
                y = -12 + a * 3 / 2;
            } else if (pattern == 1) {   // a V formation
                x = w / 2 + (i - n / 2) * (w / (n + 2));
                y = -12 + a * 3 / 2 + abs(i - n / 2) * 16;
            } else if (pattern == 2) {   // single file, weaving
                x = w / 2 + sin(a / 4) * (w / 2 - 24) / 100;
                y = -12 + a * 2;
            } else if (pattern == 3) {   // diagonal sweeps from alternating sides
                if (i % 2 == 0) x = -12 + a * 3; else x = w + 12 - a * 3;
                y = -12 + a * 3 / 2;
            } else if (pattern == 4) {   // columns dive straight down, fast
                x = w * (i + 1) / (n + 1);
                y = -12 - (i % 2) * 28 + a * 3;
            } else {                     // two mirrored weaves
                if (i % 2 == 0) x = w / 3 + sin(a / 3) * (w / 4) / 100;
                else x = w - w / 3 - sin(a / 3) * (w / 4) / 100;
                y = -12 + a * 2;
            }
            ex[k] = x; ey[k] = y;
        }

        void start() {
            if (running) return;
            running = true;
            new Thread(this).start();
        }

        void stop() { running = false; }

        public void run() {
            while (running) {
                long t0 = System.currentTimeMillis();
                step();
                repaint();
                serviceRepaints();
                long wait = 40 - (System.currentTimeMillis() - t0);
                try { Thread.sleep(wait < 5 ? 5 : wait); } catch (InterruptedException e) { }
            }
        }

        private void boom(int x, int y) {
            for (int i = 0; i < MX; i++) {
                if (xa[i] >= 12) { xx[i] = x; xy[i] = y; xa[i] = 0; return; }
            }
        }

        private void step() {
            tick++;
            for (int i = 0; i < MX; i++) if (xa[i] < 99) xa[i]++;
            if (title || over) return;
            int w = getWidth(), h = getHeight();
            int py = h - 28;
            px += move * 6;
            if (px < 12) px = 12;
            if (px > w - 12) px = w - 12;
            if (hurt > 0) hurt--;
            if (banner > 0) banner--;

            // autofire
            if (--fire <= 0) {
                fire = 6;
                shoot(px, py - 10);
                if (wave >= 4) { shoot(px - 8, py - 4); shoot(px + 8, py - 4); }
            }
            for (int i = 0; i < MB; i++) {
                if (!ba[i]) continue;
                by[i] -= 9;
                if (by[i] < -6) ba[i] = false;
            }

            // enemies
            int alive = 0;
            int firing = 160 - (wave > 10 ? 10 : wave) * 9;
            for (int k = 0; k < count; k++) {
                if (!ealive[k]) continue;
                alive++;
                if (tick < est[k]) { ex[k] = -50; ey[k] = -50; continue; }
                eage[k] = tick - est[k];
                place(k);
                if (ey[k] > h + 16 || ex[k] < -60 || ex[k] > w + 60) {
                    if (eage[k] > 10) { ealive[k] = false; continue; }
                }
                if (ey[k] > 0 && ey[k] < h - 60 && rnd(firing) == 0) enemyShoot(ex[k], ey[k] + 8);
                for (int i = 0; i < MB; i++) {
                    if (ba[i] && abs(bx[i] - ex[k]) < 10 && abs(by[i] - ey[k]) < 10) {
                        ba[i] = false;
                        if (--ehp[k] <= 0) {
                            ealive[k] = false;
                            kills++;
                            score += 10;
                            boom(ex[k], ey[k]);
                        }
                        break;
                    }
                }
                if (ealive[k] && hurt == 0 && abs(ex[k] - px) < 12 && abs(ey[k] - py) < 12) {
                    ealive[k] = false;
                    boom(ex[k], ey[k]);
                    damage(w, py);
                }
            }
            for (int i = 0; i < MEB; i++) {
                if (!eba[i]) continue;
                eby[i] += 4 + wave / 8;
                if (eby[i] > h + 4) { eba[i] = false; continue; }
                if (hurt == 0 && abs(ebx[i] - px) < 8 && abs(eby[i] - py) < 10) {
                    eba[i] = false;
                    damage(w, py);
                }
            }
            if (alive == 0 && banner == 0) {
                // clear bonus: grows with the wave, doubled when no enemy got away
                bonus = 25 * wave;
                if (kills == count) bonus *= 2;
                score += bonus;
                nextWave();
            }
        }

        private void damage(int w, int py) {
            boom(px, py);
            lives--;
            hurt = 45;
            if (lives <= 0) {
                over = true;
                if (score > best) best = score;
            }
        }

        private void shoot(int x, int y) {
            for (int i = 0; i < MB; i++) {
                if (!ba[i]) { ba[i] = true; bx[i] = x; by[i] = y; return; }
            }
        }

        private void enemyShoot(int x, int y) {
            for (int i = 0; i < MEB; i++) {
                if (!eba[i]) { eba[i] = true; ebx[i] = x; eby[i] = y; return; }
            }
        }

        private static final int[] COLORS = {0xff5050, 0xff9a30, 0xd060ff, 0x50e060, 0xffe040, 0xff60b0};

        /** One shape per wave pattern; col is the body colour. */
        private void drawEnemy(Graphics g, int x, int y, int shape, int col) {
            int dark = 0x050818;
            g.setColor(col);
            if (shape == 0) {            // dart: inverted triangle with a cockpit
                g.fillTriangle(x - 9, y - 7, x + 9, y - 7, x, y + 8);
                g.setColor(dark);
                g.fillRect(x - 2, y - 4, 4, 3);
            } else if (shape == 1) {     // diamond
                g.fillTriangle(x - 9, y, x + 9, y, x, y - 10);
                g.fillTriangle(x - 9, y, x + 9, y, x, y + 10);
                g.setColor(dark);
                g.fillRect(x - 2, y - 2, 4, 4);
            } else if (shape == 2) {     // saucer: dome and wide hull
                g.fillArc(x - 6, y - 10, 12, 12, 0, 180);
                g.fillRect(x - 11, y - 2, 22, 5);
                g.setColor(dark);
                g.fillRect(x - 7, y, 3, 2);
                g.fillRect(x - 1, y, 3, 2);
                g.fillRect(x + 5, y, 3, 2);
            } else if (shape == 3) {     // swept wing
                g.fillTriangle(x, y + 8, x - 11, y - 8, x, y - 3);
                g.fillTriangle(x, y + 8, x + 11, y - 8, x, y - 3);
                g.setColor(dark);
                g.fillRect(x - 1, y - 3, 3, 5);
            } else if (shape == 4) {     // block with side pods
                g.fillRect(x - 5, y - 8, 10, 16);
                g.fillRect(x - 10, y - 4, 4, 10);
                g.fillRect(x + 7, y - 4, 4, 10);
                g.setColor(dark);
                g.fillRect(x - 2, y - 5, 4, 4);
            } else {                     // crab: body, claws and legs
                g.fillRect(x - 7, y - 5, 14, 8);
                g.fillRect(x - 11, y - 8, 4, 8);
                g.fillRect(x + 8, y - 8, 4, 8);
                g.fillRect(x - 6, y + 3, 3, 4);
                g.fillRect(x + 4, y + 3, 3, 4);
                g.setColor(dark);
                g.fillRect(x - 4, y - 3, 3, 3);
                g.fillRect(x + 2, y - 3, 3, 3);
            }
        }

        protected void paint(Graphics g) {
            int w = getWidth(), h = getHeight();
            g.setColor(0x050818);
            g.fillRect(0, 0, w, h);

            // starfield: three speeds
            for (int i = 0; i < 40; i++) {
                int sp = 1 + i % 3;
                int y = (i * 37 + tick * sp) % h;
                g.setColor(sp == 1 ? 0x30386a : sp == 2 ? 0x6068a8 : 0xc0c8ff);
                g.fillRect((i * 71) % w, y, 1, sp);
            }
            if (title) {
                g.setColor(0x40e0ff);
                g.drawString("VOID WAVE", w / 2, h / 4, Graphics.TOP | Graphics.HCENTER);
                g.setColor(0xffffff);
                g.drawString("Survive the waves", w / 2, h / 4 + 22, Graphics.TOP | Graphics.HCENTER);
                g.drawString("Created for GenJ2", w / 2, h / 2 + 10, Graphics.TOP | Graphics.HCENTER);
                g.drawString("by Yoshi Sugawara", w / 2, h / 2 + 28, Graphics.TOP | Graphics.HCENTER);
                g.drawString("2026", w / 2, h / 2 + 46, Graphics.TOP | Graphics.HCENTER);
                if ((tick / 12) % 2 == 0) {
                    g.setColor(0x40e0ff);
                    g.drawString("Press OK to start", w / 2, h - 50, Graphics.TOP | Graphics.HCENTER);
                }
                return;
            }
            // enemies
            g.setColor(COLORS[pattern]);
            for (int k = 0; k < count; k++) {
                if (!ealive[k] || ey[k] < -12) continue;
                int x = ex[k], y = ey[k];
                drawEnemy(g, x, y, pattern, ehp[k] > 1 ? 0xffffff : COLORS[pattern]);
            }
            // bullets
            g.setColor(0x80ffff);
            for (int i = 0; i < MB; i++) if (ba[i]) g.fillRect(bx[i] - 1, by[i] - 4, 3, 8);
            g.setColor(0xff4060);
            for (int i = 0; i < MEB; i++) if (eba[i]) g.fillRect(ebx[i] - 2, eby[i] - 2, 5, 5);
            // explosions
            for (int i = 0; i < MX; i++) {
                if (xa[i] >= 12) continue;
                int r = 3 + xa[i];
                g.setColor(xa[i] < 6 ? 0xffe060 : 0xff6020);
                g.drawRect(xx[i] - r, xy[i] - r, r * 2, r * 2);
                g.fillRect(xx[i] - r / 2, xy[i] - r / 2, r, r);
            }
            // player
            if (!over && (hurt == 0 || tick % 4 < 2)) {
                int py = h - 28;
                g.setColor(0x40e0ff);
                g.fillTriangle(px, py - 12, px - 12, py + 10, px + 12, py + 10);
                g.setColor(0xffffff);
                g.fillRect(px - 1, py - 4, 3, 8);
                if (tick % 2 == 0) { g.setColor(0xff9030); g.fillRect(px - 2, py + 11, 5, 4); }
            }
            g.setColor(0xffffff);
            g.drawString("Score " + score, 4, 2, Graphics.TOP | Graphics.LEFT);
            g.drawString("Lives " + lives, w - 4, 2, Graphics.TOP | Graphics.RIGHT);
            if (banner > 0 && !over) {
                g.setColor(COLORS[pattern]);
                g.drawString("WAVE " + wave, w / 2, h / 2 - 30, Graphics.TOP | Graphics.HCENTER);
                if (wave > 1) {
                    g.setColor(0xffe040);
                    g.drawString("Clear bonus +" + bonus, w / 2, h / 2 - 10, Graphics.TOP | Graphics.HCENTER);
                }
            }
            if (over) {
                g.setColor(0xff6060);
                g.drawString("GAME OVER", w / 2, h / 2 - 30, Graphics.TOP | Graphics.HCENTER);
                g.setColor(0xffffff);
                g.drawString("Wave " + wave + "  Best " + best, w / 2, h / 2 - 10, Graphics.TOP | Graphics.HCENTER);
                g.drawString("Press OK to play", w / 2, h / 2 + 10, Graphics.TOP | Graphics.HCENTER);
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

        protected void keyReleased(int key) { if (dir(key) == move) move = 0; }
    }
}
