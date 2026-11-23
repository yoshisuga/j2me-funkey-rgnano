import javax.microedition.lcdui.*;
import javax.microedition.midlet.*;

/** Gem Swap: a match-three puzzle. Pick up a gem, swap it with a neighbour, line up three or more. */
public class GemSwap extends MIDlet implements CommandListener {
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
        private static final int[] BG_A = {0x2B1055, 0x0F2C67, 0x4A1259, 0x0B3B4F};
        private static final int[] BG_B = {0xD93F87, 0x13A3B8, 0xFF8A47, 0x7B52D3};
        private static final int COLS = 8, ROWS = 8, N = COLS * ROWS, MQ = 40;
        private static final int IDLE = 0, SWAP = 1, BACK = 2, CLEAR = 3, FALL = 4, LEVEL = 5;

        private final int[] g = new int[N], off = new int[N];
        private final boolean[] mark = new boolean[N];
        private final int[] qx = new int[MQ], qy = new int[MQ], qvx = new int[MQ], qvy = new int[MQ], ql = new int[MQ], qc = new int[MQ];

        private int cs, ox, oy;
        private int state, cur, sel, sa, sb, st, ct, lt, chain, nt;
        private int score, startScore, moves, level, best, tick, comboT, shuffleT;
        private String combo = "";
        private boolean over, running, title = true;
        private long seed = 31337;
        private Font big, small;

        Game() { reset(); }

        private int rnd(int n) {
            seed = (seed * 1103515245L + 12345L) & 0x7fffffffL;
            return (int) ((seed >> 8) % n);
        }

        private int sin(int i) { return SIN[((i % 32) + 32) % 32]; }
        private int need() { return 700 + 300 * (level - 1); }

        private int lerp(int c0, int c1, int f) {
            int r = ((c0 >> 16) & 255) * (100 - f) + ((c1 >> 16) & 255) * f;
            int gg = ((c0 >> 8) & 255) * (100 - f) + ((c1 >> 8) & 255) * f;
            int b = (c0 & 255) * (100 - f) + (c1 & 255) * f;
            return ((r / 100) << 16) | ((gg / 100) << 8) | (b / 100);
        }

        private void layout(int w, int h) {
            int a = (w - 8) / COLS, b = (h - 96) / ROWS;
            cs = a < b ? a : b;
            if (cs < 12) cs = 12;
            ox = (w - cs * COLS) / 2;
            oy = h - cs * ROWS - 18;
        }

        private void reset() {
            layout(getWidth() > 0 ? getWidth() : 240, getHeight() > 0 ? getHeight() : 320);
            score = 0; startScore = 0; moves = 20; level = 1; over = false; chain = 0;
            combo = ""; comboT = 0; shuffleT = 0;
            for (int i = 0; i < MQ; i++) ql[i] = 0;
            newBoard();
        }

        private void newBoard() {
            nt = level < 3 ? 5 : 6;
            do {
                for (int i = 0; i < N; i++) {
                    int c = i % COLS, r = i / COLS, t;
                    do {
                        t = rnd(nt);
                    } while ((c >= 2 && g[i - 1] == t && g[i - 2] == t) || (r >= 2 && g[i - COLS] == t && g[i - 2 * COLS] == t));
                    g[i] = t;
                    off[i] = 0;
                    mark[i] = false;
                }
            } while (!hasMove());
            cur = (ROWS / 2) * COLS + COLS / 2;
            sel = -1;
            state = IDLE;
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

        // MARK: rules

        /** Marks every gem in a line of three or more; returns how many. */
        private int findMatches() {
            for (int i = 0; i < N; i++) mark[i] = false;
            for (int r = 0; r < ROWS; r++) {
                int c = 0;
                while (c < COLS) {
                    int t = g[r * COLS + c], e = c + 1;
                    while (e < COLS && g[r * COLS + e] == t) e++;
                    if (e - c >= 3) for (int k = c; k < e; k++) mark[r * COLS + k] = true;
                    c = e;
                }
            }
            for (int c = 0; c < COLS; c++) {
                int r = 0;
                while (r < ROWS) {
                    int t = g[r * COLS + c], e = r + 1;
                    while (e < ROWS && g[e * COLS + c] == t) e++;
                    if (e - r >= 3) for (int k = r; k < e; k++) mark[k * COLS + c] = true;
                    r = e;
                }
            }
            int n = 0;
            for (int i = 0; i < N; i++) if (mark[i]) n++;
            return n;
        }

        private void swapCells(int a, int b) { int t = g[a]; g[a] = g[b]; g[b] = t; }

        private boolean hasMove() {
            boolean found = false;
            for (int i = 0; i < N && !found; i++) {
                int c = i % COLS, r = i / COLS;
                if (c < COLS - 1) {
                    swapCells(i, i + 1);
                    if (findMatches() > 0) found = true;
                    swapCells(i, i + 1);
                }
                if (!found && r < ROWS - 1) {
                    swapCells(i, i + COLS);
                    if (findMatches() > 0) found = true;
                    swapCells(i, i + COLS);
                }
            }
            for (int i = 0; i < N; i++) mark[i] = false;
            return found;
        }

        private int gemColor(int t) { return RB[t % 6]; }

        private void sparkle(int cell) {
            int x = ox + (cell % COLS) * cs + cs / 2, y = oy + (cell / COLS) * cs + cs / 2;
            int n = 0;
            for (int i = 0; i < MQ && n < 3; i++) {
                if (ql[i] > 0) continue;
                qx[i] = x; qy[i] = y; qvx[i] = rnd(9) - 4; qvy[i] = -rnd(5) - 1; ql[i] = 12 + rnd(8); qc[i] = RB[rnd(6)];
                n++;
            }
        }

        private void startClear() { state = CLEAR; ct = 0; }

        private void doClear() {
            int n = 0;
            for (int i = 0; i < N; i++) if (mark[i]) n++;
            int pts = n * 10 * chain + (n >= 5 ? n * 10 : 0);
            score += pts;
            if (chain >= 2) { combo = "CHAIN x" + chain; comboT = 36; }
            else if (n >= 5) { combo = "AMAZING!"; comboT = 36; }
            else if (n == 4) { combo = "NICE!"; comboT = 24; }
            for (int i = 0; i < N; i++) if (mark[i]) sparkle(i);
            // gems fall into the holes and new ones drop in from above
            for (int c = 0; c < COLS; c++) {
                int w = ROWS - 1;
                for (int r = ROWS - 1; r >= 0; r--) {
                    int i = r * COLS + c;
                    if (mark[i]) continue;
                    if (w != r) { g[w * COLS + c] = g[i]; off[w * COLS + c] = (w - r) * cs; }
                    w--;
                }
                for (int r = 0; r <= w; r++) { g[r * COLS + c] = rnd(nt); off[r * COLS + c] = (w + 1) * cs; }
            }
            for (int i = 0; i < N; i++) mark[i] = false;
            state = FALL;
        }

        private void settle() {
            chain = 0;
            if (score - startScore >= need()) {
                int bonus = moves * 10;
                score += bonus;
                startScore = score;
                level++;
                moves = 20;
                combo = "LEVEL " + (level - 1) + " CLEAR!  +" + bonus;
                comboT = 60;
                state = LEVEL;
                lt = 60;
                return;
            }
            if (moves <= 0) {
                over = true;
                if (score > best) best = score;
                return;
            }
            if (!hasMove()) {
                newBoard();
                shuffleT = 40;
            }
            state = IDLE;
        }

        private void step() {
            tick++;
            for (int i = 0; i < MQ; i++) {
                if (ql[i] > 0) { ql[i]--; qx[i] += qvx[i]; qy[i] += qvy[i]; qvy[i] += 1; }
            }
            if (comboT > 0) comboT--;
            if (shuffleT > 0) shuffleT--;
            if (title || over) return;

            if (state == SWAP || state == BACK) {
                st++;
                if (st >= 6) {
                    swapCells(sa, sb);
                    if (state == SWAP) {
                        if (findMatches() > 0) { moves--; chain = 1; startClear(); }
                        else { state = BACK; st = 0; }
                    } else {
                        state = IDLE;
                    }
                }
            } else if (state == CLEAR) {
                ct++;
                if (ct >= 10) doClear();
            } else if (state == FALL) {
                boolean moving = false;
                for (int i = 0; i < N; i++) {
                    if (off[i] > 0) { off[i] -= 7; if (off[i] < 0) off[i] = 0; if (off[i] > 0) moving = true; }
                }
                if (!moving) {
                    if (findMatches() > 0) { chain++; startClear(); }
                    else settle();
                }
            } else if (state == LEVEL) {
                lt--;
                if (lt <= 0) newBoard();
            }
        }

        // MARK: drawing

        private void shadowText(Graphics gr, String s, int x, int y, int anchor) {
            gr.setColor(0x20103A);
            gr.drawString(s, x + 1, y + 1, anchor);
            gr.setColor(0xFFFFFF);
            gr.drawString(s, x, y, anchor);
        }

        private void rainbowText(Graphics gr, String s, int w, int y, Font f) {
            gr.setFont(f);
            int x = (w - f.stringWidth(s)) / 2;
            for (int i = 0; i < s.length(); i++) {
                char c = s.charAt(i);
                gr.setColor(0x20103A);
                gr.drawChar(c, x + 1, y + 1, Graphics.TOP | Graphics.LEFT);
                gr.setColor(RB[(i + tick / 6) % 6]);
                gr.drawChar(c, x, y, Graphics.TOP | Graphics.LEFT);
                x += f.charWidth(c);
            }
        }

        private void drawGem(Graphics gr, int t, int x, int y, int s, boolean flash) {
            int cx = x + s / 2, cy = y + s / 2, p = s / 8 + 1;
            gr.setColor(flash ? 0xFFFFFF : gemColor(t));
            if (t == 0) {
                gr.fillArc(x + p, y + p, s - 2 * p, s - 2 * p, 0, 360);
            } else if (t == 1) {
                gr.fillTriangle(cx, y + p, x + p, cy, x + s - p, cy);
                gr.fillTriangle(cx, y + s - p, x + p, cy, x + s - p, cy);
            } else if (t == 2) {
                gr.fillTriangle(cx, y + p - 1, x + p, y + s - p - 3, x + s - p, y + s - p - 3);
                gr.fillTriangle(cx, y + s - p, x + p, y + p + 4, x + s - p, y + p + 4);
            } else if (t == 3) {
                gr.fillRect(x + p + 1, y + p + 1, s - 2 * p - 2, s - 2 * p - 2);
            } else if (t == 4) {
                gr.fillTriangle(cx, y + p, x + p, y + s - p, x + s - p, y + s - p);
            } else {
                gr.fillRect(x + p + 1, cy - 1, s - 2 * p - 2, s / 2 - p);
                gr.fillTriangle(cx, y + p, x + p + 1, cy, x + s - p - 1, cy);
            }
            if (!flash) {
                gr.setColor(0xFFFFFF);
                gr.fillRect(x + p + 2, y + p + 2, 3, 3);
            }
        }

        private void drawBackground(Graphics gr, int w, int h) {
            int k = (tick / 300) % 4, nxt = (k + 1) % 4, f = (tick % 300) * 100 / 300;
            int a = lerp(BG_A[k], BG_A[nxt], f), b = lerp(BG_B[k], BG_B[nxt], f);
            for (int i = 0; i < 24; i++) {
                int y0 = h * i / 24, y1 = h * (i + 1) / 24;
                gr.setColor(lerp(a, b, i * 100 / 23));
                gr.fillRect(0, y0, w, y1 - y0 + 1);
            }
            // a few drifting sparkles
            for (int i = 0; i < 14; i++) {
                int x = (i * 53 + tick / (2 + i % 3)) % w, y = (i * 71 + 11) % h;
                gr.setColor(((tick / 8) + i) % 4 == 0 ? 0xFFFFFF : lerp(a, 0xFFFFFF, 40));
                gr.fillRect(x, y, 2, 2);
            }
        }

        protected void paint(Graphics gr) {
            int w = getWidth(), h = getHeight();
            if (big == null) {
                big = Font.getFont(Font.FACE_PROPORTIONAL, Font.STYLE_BOLD, Font.SIZE_LARGE);
                small = Font.getFont(Font.FACE_PROPORTIONAL, Font.STYLE_BOLD, Font.SIZE_SMALL);
            }
            layout(w, h);
            drawBackground(gr, w, h);
            if (title) { paintTitle(gr, w, h); return; }

            // board
            gr.setColor(0x20103A);
            gr.fillRect(ox - 4, oy - 4, cs * COLS + 8, cs * ROWS + 8);
            for (int c = 0; c < 6; c++) { gr.setColor(RB[c]); gr.fillRect(ox - 4, oy - 4 + c, cs * COLS + 8, 1); }
            for (int i = 0; i < N; i++) {
                int x = ox + (i % COLS) * cs, y = oy + (i / COLS) * cs;
                gr.setColor(((i % COLS) + (i / COLS)) % 2 == 0 ? 0x3A2268 : 0x2E1A54);
                gr.fillRect(x, y, cs, cs);
            }
            gr.setClip(ox, oy, cs * COLS, cs * ROWS);
            for (int i = 0; i < N; i++) {
                if (g[i] < 0) continue;
                int x = ox + (i % COLS) * cs, y = oy + (i / COLS) * cs - off[i];
                if ((state == SWAP || state == BACK) && (i == sa || i == sb)) continue;
                boolean flash = state == CLEAR && mark[i] && (ct / 2) % 2 == 0;
                if (state == CLEAR && mark[i] && ct > 6) { int sh = (10 - ct) * cs / 8; drawGem(gr, g[i], x + sh / 2, y + sh / 2, cs - sh, flash); }
                else drawGem(gr, g[i], x, y, cs, flash);
            }
            if (state == SWAP || state == BACK) {
                int ax = ox + (sa % COLS) * cs, ay = oy + (sa / COLS) * cs;
                int bx = ox + (sb % COLS) * cs, by = oy + (sb / COLS) * cs;
                int p = st * 100 / 6;
                drawGem(gr, g[sa], ax + (bx - ax) * p / 100, ay + (by - ay) * p / 100, cs, false);
                drawGem(gr, g[sb], bx + (ax - bx) * p / 100, by + (ay - by) * p / 100, cs, false);
            }
            gr.setClip(0, 0, w, h);

            // cursor: a frame, brighter while a gem is picked up
            if (state == IDLE && !over) {
                int x = ox + (cur % COLS) * cs, y = oy + (cur / COLS) * cs;
                gr.setColor(sel >= 0 ? 0xFFD60A : 0xFFFFFF);
                gr.drawRect(x, y, cs - 1, cs - 1);
                gr.drawRect(x + 1, y + 1, cs - 3, cs - 3);
                if (sel >= 0 && (tick / 4) % 2 == 0) gr.drawRect(x + 2, y + 2, cs - 5, cs - 5);
            }
            for (int i = 0; i < MQ; i++) {
                if (ql[i] > 0) { gr.setColor(qc[i]); gr.fillRect(qx[i], qy[i], 3, 3); }
            }

            // top bar: level, score, progress to the next level, moves
            gr.setFont(small);
            shadowText(gr, "Level " + level, 6, 4, Graphics.TOP | Graphics.LEFT);
            shadowText(gr, "Score " + score, w - 6, 4, Graphics.TOP | Graphics.RIGHT);
            int bw = w - 12, by = 28;
            gr.setColor(0x20103A);
            gr.fillRect(5, by - 1, bw + 2, 12);
            int fill = (score - startScore) * bw / need();
            if (fill > bw) fill = bw;
            if (fill < 0) fill = 0;
            for (int x = 0; x < fill; x += 4) {
                gr.setColor(RB[(x / 24) % 6]);
                gr.fillRect(6 + x, by, 4 > fill - x ? fill - x : 4, 10);
            }
            shadowText(gr, "Moves " + moves, w / 2, 44, Graphics.TOP | Graphics.HCENTER);
            if (moves <= 5 && moves > 0 && (tick / 8) % 2 == 0) {
                gr.setColor(0xFF3B30);
                gr.drawRect(w / 2 - 36, 42, 72, 16);
            }

            if (comboT > 0 && !over) rainbowText(gr, combo, w, oy + cs * ROWS / 2 - 10, big);
            if (shuffleT > 0) shadowText(gr, "No moves left - shuffled!", w / 2, oy - 18, Graphics.TOP | Graphics.HCENTER);
            if (tick < 160 && state == IDLE) shadowText(gr, "OK picks up a gem, arrows swap it", w / 2, h - 14, Graphics.TOP | Graphics.HCENTER);

            if (over) {
                int pw = w - 24, px = 12, py = h / 2 - 50;
                gr.setColor(0x20103A);
                gr.fillRect(px, py, pw, 100);
                for (int c = 0; c < 6; c++) { gr.setColor(RB[c]); gr.fillRect(px, py + c * 2, pw, 2); }
                gr.setColor(0xFFFFFF);
                gr.fillRect(px + 2, py + 12, pw - 4, 86);
                gr.setColor(0x20103A);
                gr.setFont(big);
                gr.drawString("Out of moves", w / 2, py + 16, Graphics.TOP | Graphics.HCENTER);
                gr.setFont(small);
                gr.drawString("Level " + level + "   Score " + score, w / 2, py + 44, Graphics.TOP | Graphics.HCENTER);
                gr.drawString("Best " + best, w / 2, py + 60, Graphics.TOP | Graphics.HCENTER);
                gr.drawString("Press OK to play again", w / 2, py + 78, Graphics.TOP | Graphics.HCENTER);
            }
        }

        private void paintTitle(Graphics gr, int w, int h) {
            int cx = w / 2;
            rainbowText(gr, "GEM", w, h / 6, big);
            rainbowText(gr, "SWAP", w, h / 6 + big.getHeight() + 2, big);
            int s = 32, x0 = (w - 6 * s - 5 * 4) / 2;
            for (int i = 0; i < 6; i++) {
                int bob = sin(tick + i * 5) * 8 / 100;
                drawGem(gr, i, x0 + i * (s + 4), h * 42 / 100 + bob, s, false);
            }
            gr.setFont(small);
            shadowText(gr, "Match three or more", cx, h * 58 / 100, Graphics.TOP | Graphics.HCENTER);
            shadowText(gr, "Created for GenJ2", cx, h * 70 / 100, Graphics.TOP | Graphics.HCENTER);
            shadowText(gr, "by Yoshi Sugawara", cx, h * 70 / 100 + 15, Graphics.TOP | Graphics.HCENTER);
            shadowText(gr, "2026", cx, h * 70 / 100 + 30, Graphics.TOP | Graphics.HCENTER);
            if ((tick / 12) % 2 == 0) shadowText(gr, "Press OK to start", cx, h - 24, Graphics.TOP | Graphics.HCENTER);
        }

        // MARK: input

        /** 1 left, 2 right, 3 up, 4 down, 0 other. */
        private int dir(int key) {
            int a = getGameAction(key);
            if (a == LEFT || key == Canvas.KEY_NUM4) return 1;
            if (a == RIGHT || key == Canvas.KEY_NUM6) return 2;
            if (a == UP || key == Canvas.KEY_NUM2) return 3;
            if (a == DOWN || key == Canvas.KEY_NUM8) return 4;
            return 0;
        }

        protected void keyPressed(int key) {
            int d = dir(key);
            boolean fire = getGameAction(key) == FIRE || key == Canvas.KEY_NUM5;
            if (title) { if (fire) { title = false; reset(); } return; }
            if (over) { if (fire) reset(); return; }
            if (state != IDLE) return;
            int c = cur % COLS, r = cur / COLS;
            if (fire) { sel = sel >= 0 ? -1 : cur; return; }
            if (d == 0) return;
            int nc = c, nr = r;
            if (d == 1) nc--;
            else if (d == 2) nc++;
            else if (d == 3) nr--;
            else nr++;
            if (nc < 0 || nc >= COLS || nr < 0 || nr >= ROWS) return;
            if (sel >= 0) {                       // swap the picked-up gem with its neighbour
                sa = cur; sb = nr * COLS + nc; sel = -1; st = 0; state = SWAP;
            } else {
                cur = nr * COLS + nc;
            }
        }

        protected void keyRepeated(int key) { keyPressed(key); }
    }
}
