import javax.microedition.lcdui.*;
import javax.microedition.midlet.*;

/** Rainbow Hop: bounce up through colourful skies on floating islands, leaving a rainbow behind you. */
public class RainbowHop extends MIDlet implements CommandListener {
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
        private static final int[] SIN = {0, 20, 38, 56, 71, 83, 92, 98, 100, 98, 92, 83, 71, 56, 38, 20,
                                          0, -20, -38, -56, -71, -83, -92, -98, -100, -98, -92, -83, -71, -56, -38, -20};
        private static final int[] RB = {0xFF3B30, 0xFF9500, 0xFFD60A, 0x34C759, 0x32ADE6, 0xAF52DE};
        // a sky per stage: day, sunset, candy, night, aurora
        private static final int[] SKY_TOP = {0x4FB3F6, 0xFF8FA3, 0x9C6BFF, 0x120C4A, 0x00B894};
        private static final int[] SKY_BOT = {0xC6F1FF, 0xFFE3A3, 0xFFB8E0, 0x5A2D91, 0xC8FF8A};
        private static final int MP = 12, MS = 6, MN = 3, MQ = 24, PW = 44, TR = 14, STAGE = 800;

        // islands: type 0 grass, 1 moving, 2 crumbling, 3 spring
        private final int[] plb = new int[MP], plx = new int[MP], ply = new int[MP], plt = new int[MP], pld = new int[MP], plc = new int[MP];
        private final boolean[] pla = new boolean[MP];
        // stars
        private final int[] sx = new int[MS], sy = new int[MS];
        private final boolean[] sa = new boolean[MS];
        // critters
        private final int[] nx = new int[MN], ny = new int[MN], nph = new int[MN];
        private final boolean[] na = new boolean[MN];
        // sparkles
        private final int[] qx = new int[MQ], qy = new int[MQ], qvx = new int[MQ], qvy = new int[MQ], ql = new int[MQ], qc = new int[MQ];
        // rainbow trail
        private final int[] tx = new int[TR], ty = new int[TR];

        private int lastCx, px, py, vy, move, face, tick, topY, scroll, bonus, best, topColor, botColor;
        private boolean night, over, running, title = true;
        private long seed = 4242;
        private Font big, small;

        Game() { reset(); }

        private int rnd(int n) {
            seed = (seed * 1103515245L + 12345L) & 0x7fffffffL;
            return (int) ((seed >> 8) % n);
        }

        private int sin(int i) { return SIN[((i % 32) + 32) % 32]; }
        private int abs(int v) { return v < 0 ? -v : v; }
        private int score() { return scroll / 4 + bonus; }

        private int lerp(int c0, int c1, int f) {
            int r = ((c0 >> 16) & 255) * (100 - f) + ((c1 >> 16) & 255) * f;
            int g = ((c0 >> 8) & 255) * (100 - f) + ((c1 >> 8) & 255) * f;
            int b = (c0 & 255) * (100 - f) + (c1 & 255) * f;
            return ((r / 100) << 16) | ((g / 100) << 8) | (b / 100);
        }

        private void reset() {
            int w = getWidth() > 0 ? getWidth() : 240;
            int h = getHeight() > 0 ? getHeight() : 320;
            for (int i = 0; i < MP; i++) pla[i] = false;
            for (int i = 0; i < MS; i++) sa[i] = false;
            for (int i = 0; i < MN; i++) na[i] = false;
            for (int i = 0; i < MQ; i++) ql[i] = 0;
            scroll = 0; bonus = 0; over = false; move = 0; face = 1;
            // a wide first island under the player
            plx[0] = w / 2 - PW / 2; plb[0] = plx[0]; lastCx = w / 2; ply[0] = h - 24; plt[0] = 0; pld[0] = 0; plc[0] = 0; pla[0] = true;
            topY = ply[0];
            px = w / 2; py = ply[0]; vy = -13;
            for (int i = 0; i < TR; i++) { tx[i] = px; ty[i] = py - 8; }
            while (topY > -30) spawn(w);
        }

        private void spawn(int w) {
            int slot = -1;
            for (int i = 0; i < MP; i++) if (!pla[i]) { slot = i; break; }
            if (slot < 0) { topY = -100; return; }
            int level = scroll / 100;
            int gap = 38 + rnd(20) + (level / 6 > 14 ? 14 : level / 6);
            int y = topY - gap;
            // a jump carries about 100 px sideways: the next island is never further than 60 px from the last one
            int x = lastCx - PW / 2 + rnd(121) - 60;
            if (x < 0) x = 0;
            if (x > w - PW) x = w - PW;
            lastCx = x + PW / 2;
            int r = rnd(100);
            int t = 0;
            if (level >= 2 && r < 18) t = 1;
            else if (level >= 4 && r < 30) t = 2;
            else if (level >= 1 && r >= 90) t = 3;
            plx[slot] = x; plb[slot] = x; ply[slot] = y; plt[slot] = t; plc[slot] = 0; pla[slot] = true;
            pld[slot] = rnd(2) == 0 ? -1 : 1;
            topY = y;
            if (rnd(4) == 0) {                         // a star over the island
                for (int i = 0; i < MS; i++) if (!sa[i]) { sa[i] = true; sx[i] = x + PW / 2; sy[i] = y - 24; break; }
            }
            if (level >= 5 && t == 0 && rnd(6) == 0) { // a critter in the air between islands
                for (int i = 0; i < MN; i++) if (!na[i]) { na[i] = true; nx[i] = rnd(w - 40) + 20; ny[i] = y + gap / 2; nph[i] = rnd(32); break; }
            }
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

        private void sparkle(int x, int y) {
            int n = 0;
            for (int i = 0; i < MQ && n < 10; i++) {
                if (ql[i] > 0) continue;
                qx[i] = x; qy[i] = y; qvx[i] = rnd(9) - 4; qvy[i] = -rnd(5) - 1; ql[i] = 12 + rnd(6); qc[i] = RB[rnd(6)];
                n++;
            }
        }

        private void die() {
            over = true;
            if (score() > best) best = score();
        }

        private void step() {
            tick++;
            for (int i = 0; i < MQ; i++) {
                if (ql[i] > 0) { ql[i]--; qx[i] += qvx[i]; qy[i] += qvy[i]; qvy[i] += 1; }
            }
            if (title || over) return;
            int w = getWidth(), h = getHeight();

            // move, with the screen wrapping at the sides
            px += move * 4;
            if (px < -6) px = w + 6;
            if (px > w + 6) px = -6;
            if (move != 0) face = move;

            int oldy = py;
            vy += 1;
            if (vy > 14) vy = 14;
            py += vy;

            for (int i = 0; i < MP; i++) {
                if (!pla[i]) continue;
                if (plt[i] == 1) {
                    plx[i] += pld[i] * 2;
                    // moving islands stay within 40 px of where they were placed
                    int lo = plb[i] - 40 < 0 ? 0 : plb[i] - 40, hi = plb[i] + 40 > w - PW ? w - PW : plb[i] + 40;
                    if (plx[i] < lo) { plx[i] = lo; pld[i] = 1; }
                    if (plx[i] > hi) { plx[i] = hi; pld[i] = -1; }
                }
                if (plc[i] > 0) {
                    plc[i]--;
                    if (plc[i] == 0) pla[i] = false;
                }
            }
            if (vy > 0) {
                for (int i = 0; i < MP; i++) {
                    if (!pla[i]) continue;
                    if (px + 6 > plx[i] && px - 6 < plx[i] + PW && oldy <= ply[i] + 1 && py >= ply[i]) {
                        py = ply[i];
                        vy = plt[i] == 3 ? -21 : -13;
                        if (plt[i] == 2 && plc[i] == 0) plc[i] = 6;
                        sparkle(px, py);
                        break;
                    }
                }
            }
            for (int i = 0; i < MS; i++) {
                if (sa[i] && abs(sx[i] - px) < 12 && abs(sy[i] - (py - 8)) < 14) {
                    sa[i] = false;
                    bonus += 25;
                    sparkle(sx[i], sy[i]);
                }
            }
            for (int i = 0; i < MN; i++) {
                if (!na[i]) continue;
                int ex = nx[i] + sin(tick / 2 + nph[i]) * 22 / 100;
                int ey = ny[i] + sin(tick / 3 + nph[i] + 8) * 6 / 100;
                if (abs(ex - px) < 13 && abs(ey - (py - 8)) < 14) {
                    if (vy > 0 && oldy <= ey + 2) {     // landed on it
                        na[i] = false;
                        vy = -14;
                        bonus += 50;
                        sparkle(ex, ey);
                    } else {
                        die();
                        return;
                    }
                }
            }

            // the world scrolls down as we climb
            if (py < h / 3) {
                int d = h / 3 - py;
                py += d; topY += d; scroll += d;
                for (int i = 0; i < MP; i++) if (pla[i]) { ply[i] += d; if (ply[i] > h + 10) pla[i] = false; }
                for (int i = 0; i < MS; i++) if (sa[i]) { sy[i] += d; if (sy[i] > h + 10) sa[i] = false; }
                for (int i = 0; i < MN; i++) if (na[i]) { ny[i] += d; if (ny[i] > h + 20) na[i] = false; }
                for (int i = 0; i < TR; i++) ty[i] += d;
                for (int i = 0; i < MQ; i++) qy[i] += d;
            }
            while (topY > -30) spawn(w);

            // the rainbow trail
            for (int i = 0; i < TR - 1; i++) { tx[i] = tx[i + 1]; ty[i] = ty[i + 1]; }
            tx[TR - 1] = px; ty[TR - 1] = py - 8;

            if (py - 16 > h) die();
        }

        // MARK: drawing

        private void computeSky() {
            int stage = (scroll / STAGE) % 5, m = scroll % STAGE;
            int f = m > 500 ? (m - 500) * 100 / 300 : 0;
            int nxt = (stage + 1) % 5;
            topColor = lerp(SKY_TOP[stage], SKY_TOP[nxt], f);
            botColor = lerp(SKY_BOT[stage], SKY_BOT[nxt], f);
            night = f < 50 ? stage == 3 : nxt == 3;
        }

        private int skyAt(int y, int h) { return lerp(topColor, botColor, y * 100 / h); }

        private void shadowText(Graphics g, String s, int x, int y, int anchor) {
            g.setColor(0x202040);
            g.drawString(s, x + 1, y + 1, anchor);
            g.setColor(0xFFFFFF);
            g.drawString(s, x, y, anchor);
        }

        private void rainbowText(Graphics g, String s, int w, int y, Font f) {
            g.setFont(f);
            int x = (w - f.stringWidth(s)) / 2;
            for (int i = 0; i < s.length(); i++) {
                char c = s.charAt(i);
                g.setColor(0x202040);
                g.drawChar(c, x + 1, y + 1, Graphics.TOP | Graphics.LEFT);
                g.setColor(RB[i % 6]);
                g.drawChar(c, x, y, Graphics.TOP | Graphics.LEFT);
                x += f.charWidth(c);
            }
        }

        private void drawIsland(Graphics g, int x, int y, int t, int crumble) {
            int top, body, under;
            if (t == 1) { top = 0x4DD0E1; body = 0x1C7C96; under = 0x14566B; }
            else if (t == 2) { top = 0xFF7EB6; body = 0xB03A72; under = 0x7A2450; }
            else if (t == 3) { top = 0xFFD60A; body = 0xC77700; under = 0x8A5200; }
            else { top = 0x4CD964; body = 0x9A6A3A; under = 0x6B4423; }
            int shake = crumble > 0 ? (crumble % 2 == 0 ? -1 : 1) : 0;
            x += shake;
            g.setColor(under);
            g.fillTriangle(x + 5, y + 9, x + PW - 5, y + 9, x + PW / 2, y + 20);
            g.setColor(body);
            g.fillRect(x + 1, y + 4, PW - 2, 6);
            g.setColor(top);
            g.fillRect(x + 2, y, PW - 4, 5);
            g.fillArc(x - 1, y, 7, 6, 0, 360);
            g.fillArc(x + PW - 6, y, 7, 6, 0, 360);
            if (t == 0) {                               // flowers on the grass
                g.setColor(0xFF3B30); g.fillRect(x + 9, y - 2, 3, 3);
                g.setColor(0xFFFFFF); g.fillRect(x + PW - 14, y - 2, 3, 3);
            } else if (t == 3) {                        // a spring
                g.setColor(0xFF3B30); g.fillRect(x + PW / 2 - 6, y - 6, 12, 6);
                g.setColor(0xFFFFFF); g.fillRect(x + PW / 2 - 6, y - 4, 12, 1);
            } else if (t == 2) {
                g.setColor(0x7A2450); g.fillRect(x + 12, y + 5, 2, 4); g.fillRect(x + 28, y + 5, 2, 4);
            }
        }

        private void drawStar(Graphics g, int x, int y) {
            g.setColor((tick / 4) % 2 == 0 ? 0xFFD60A : 0xFFF59D);
            g.fillTriangle(x, y - 8, x - 7, y + 4, x + 7, y + 4);
            g.fillTriangle(x, y + 8, x - 7, y - 4, x + 7, y - 4);
            g.setColor(0xFF9500);
            g.fillRect(x - 1, y - 1, 3, 3);
        }

        private void drawCritter(Graphics g, int x, int y) {
            int flap = sin(tick) * 5 / 100;
            g.setColor(0xFFFFFF);
            g.fillTriangle(x - 7, y - 2, x - 19, y - 8 + flap, x - 7, y + 4);
            g.fillTriangle(x + 7, y - 2, x + 19, y - 8 + flap, x + 7, y + 4);
            g.setColor(0x7E57C2);
            g.fillArc(x - 9, y - 9, 18, 18, 0, 360);
            g.setColor(0xFFFFFF);
            g.fillRect(x - 5, y - 4, 4, 4); g.fillRect(x + 1, y - 4, 4, 4);
            g.setColor(0x202040);
            g.fillRect(x - 4, y - 3, 2, 3); g.fillRect(x + 2, y - 3, 2, 3);
            g.setColor(0xFF3B30);
            g.fillRect(x - 3, y + 3, 6, 2);
        }

        private void drawPlayer(Graphics g, int x, int y) {
            g.setColor(0xC2185B);
            g.fillRect(x - 6, y - 3, 5, 3);
            g.fillRect(x + 1, y - 3, 5, 3);
            g.setColor(0xFF7BAC);
            g.fillArc(x - 8, y - 17, 16, 16, 0, 360);
            g.setColor(0xFFC1DA);
            g.fillArc(x - 5, y - 14, 6, 5, 0, 360);
            g.setColor(0xFFFFFF);
            g.fillRect(x - 5 + face, y - 12, 4, 4);
            g.fillRect(x + 1 + face, y - 12, 4, 4);
            g.setColor(0x202040);
            g.fillRect(x - 4 + face + face / 2, y - 11, 2, 3);
            g.fillRect(x + 2 + face + face / 2, y - 11, 2, 3);
            g.setColor(0xC2185B);
            g.fillRect(x - 2, y - 6, 4, 1);
            g.setColor(RB[(tick / 3) % 6]);          // a sparkling tuft
            g.fillRect(x - 1, y - 22, 3, 5);
            g.fillRect(x - 2, y - 20, 5, 2);
        }

        private void drawTrail(Graphics g) {
            for (int i = 0; i < TR - 1; i++) {
                int y0 = ty[i], y1 = ty[i + 1];
                int top = y0 < y1 ? y0 : y1;
                int len = abs(y1 - y0) + 2;
                int scale = 100 * (i + 1) / TR;           // narrower towards the old end
                for (int c = 0; c < 6; c++) {
                    int off = (c - 3) * 3 * scale / 100;
                    g.setColor(RB[c]);
                    g.fillRect(tx[i] + off, top, 3, len);
                }
            }
        }

        protected void paint(Graphics g) {
            int w = getWidth(), h = getHeight();
            if (big == null) {
                big = Font.getFont(Font.FACE_PROPORTIONAL, Font.STYLE_BOLD, Font.SIZE_LARGE);
                small = Font.getFont(Font.FACE_PROPORTIONAL, Font.STYLE_BOLD, Font.SIZE_SMALL);
            }
            computeSky();
            for (int i = 0; i < 24; i++) {
                int y0 = h * i / 24, y1 = h * (i + 1) / 24;
                g.setColor(lerp(topColor, botColor, i * 100 / 23));
                g.fillRect(0, y0, w, y1 - y0 + 1);
            }
            if (night) {
                for (int i = 0; i < 28; i++) {
                    g.setColor(((tick / 6) + i) % 5 == 0 ? 0xFFFFFF : 0xB8B8FF);
                    g.fillRect((i * 97 + 13) % w, (i * 53 + 7) % h, 2, 2);
                }
                g.setColor(0xF5F0D0);
                g.fillArc(w - 52, 22, 30, 30, 0, 360);
                g.setColor(skyAt(32, h));
                g.fillArc(w - 44, 18, 28, 28, 0, 360);
            } else {
                g.setColor(0xFFF2A8);
                g.fillArc(w - 58, 16, 44, 44, 0, 360);
                g.setColor(0xFFE066);
                g.fillArc(w - 52, 22, 32, 32, 0, 360);
            }
            // clouds drift down as the screen climbs
            g.setColor(night ? 0xC9B6FF : 0xFFFFFF);
            for (int i = 0; i < 4; i++) {
                int cy = ((i * 90 + 30 + scroll / 3) % (h + 80)) - 40;
                int cx = (i * 71 + 25) % (w - 20);
                g.fillArc(cx, cy, 34, 18, 0, 360);
                g.fillArc(cx + 14, cy - 8, 30, 20, 0, 360);
                g.fillArc(cx + 28, cy, 30, 18, 0, 360);
            }

            if (title) { paintTitle(g, w, h); return; }

            for (int i = 0; i < MP; i++) if (pla[i]) drawIsland(g, plx[i], ply[i], plt[i], plc[i]);
            for (int i = 0; i < MS; i++) if (sa[i]) drawStar(g, sx[i], sy[i]);
            for (int i = 0; i < MN; i++) {
                if (!na[i]) continue;
                drawCritter(g, nx[i] + sin(tick / 2 + nph[i]) * 22 / 100, ny[i] + sin(tick / 3 + nph[i] + 8) * 6 / 100);
            }
            drawTrail(g);
            drawPlayer(g, px, py);
            if (px < 8) drawPlayer(g, px + w + 12, py);        // wrapping across the edge
            if (px > w - 8) drawPlayer(g, px - w - 12, py);
            for (int i = 0; i < MQ; i++) {
                if (ql[i] > 0) { g.setColor(qc[i]); g.fillRect(qx[i], qy[i], 3, 3); }
            }

            g.setFont(small);
            shadowText(g, "Score " + score(), 4, 2, Graphics.TOP | Graphics.LEFT);
            shadowText(g, "Best " + (best > score() ? best : score()), w - 4, 2, Graphics.TOP | Graphics.RIGHT);

            if (over) {
                int bw = w - 24, bx = 12, by = h / 2 - 50;
                g.setColor(0x202040);
                g.fillRect(bx, by, bw, 100);
                for (int c = 0; c < 6; c++) { g.setColor(RB[c]); g.fillRect(bx, by + c * 2, bw, 2); }
                g.setColor(0xFFFFFF);
                g.fillRect(bx + 2, by + 12, bw - 4, 86);
                g.setColor(0x202040);
                g.setFont(big);
                g.drawString("Oh no!", w / 2, by + 16, Graphics.TOP | Graphics.HCENTER);
                g.setFont(small);
                g.drawString("Height " + (scroll / 4) + "   Stars " + (bonus / 25), w / 2, by + 42, Graphics.TOP | Graphics.HCENTER);
                g.drawString("Score " + score() + "   Best " + best, w / 2, by + 58, Graphics.TOP | Graphics.HCENTER);
                g.drawString("Press OK to retry", w / 2, by + 76, Graphics.TOP | Graphics.HCENTER);
            }
        }

        private void paintTitle(Graphics g, int w, int h) {
            int cx = w / 2, R = w * 42 / 100, base = h * 5 / 12;
            for (int c = 0; c < 6; c++) {
                g.setColor(RB[c]);
                g.fillArc(cx - R + c * 7, base - R + c * 7, 2 * (R - c * 7), 2 * (R - c * 7), 0, 180);
            }
            g.setColor(skyAt(base - 25, h));
            g.fillArc(cx - (R - 42), base - (R - 42), 2 * (R - 42), 2 * (R - 42), 0, 180);
            g.setColor(skyAt(base, h));
            g.fillRect(cx - R, base, 2 * R + 1, 2);

            rainbowText(g, "RAINBOW", w, base + 8, big);
            rainbowText(g, "HOP", w, base + 8 + big.getHeight() + 2, big);

            // a hopping friend on an island
            int iy = h * 4 / 5;
            drawIsland(g, cx - PW / 2, iy, 0, 0);
            int hop = sin(tick) * 14 / 100;
            if (hop < 0) hop = -hop;
            face = sin(tick / 2) > 0 ? 1 : -1;
            drawPlayer(g, cx, iy - hop * 2);

            g.setFont(small);
            shadowText(g, "Created for GenJ2", cx, iy - 84, Graphics.TOP | Graphics.HCENTER);
            shadowText(g, "by Yoshi Sugawara", cx, iy - 69, Graphics.TOP | Graphics.HCENTER);
            shadowText(g, "2026", cx, iy - 54, Graphics.TOP | Graphics.HCENTER);
            if ((tick / 12) % 2 == 0) shadowText(g, "Press OK to start", cx, h - 22, Graphics.TOP | Graphics.HCENTER);
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
