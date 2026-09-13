"""Real-time GUI viewer for easicam monitor CSV (monitor-easicam.ps1 v2 format).

Usage:  python monitor-viewer.py [csv_path]
Default csv: <脚本目录>\..\logs\easicam-monitor-v2.csv

Panels: handles / cpu / memory (ws+priv) / gdi+user objects.
- Tail-follows the CSV every 2s (incremental read).
- Splits curves when PID changes (crash/restart visible as a gap).
- Event lines (note column) are drawn on the handles panel.
- Pan/zoom with the toolbar; autoscale resumes when toolbar is idle.
"""
import datetime as dt
import os
import sys
import threading
import tkinter as tk
from pathlib import Path
from tkinter import ttk

import matplotlib

matplotlib.use("TkAgg")
import matplotlib.dates as mdates
from matplotlib.backends.backend_tkagg import FigureCanvasTkAgg, NavigationToolbar2Tk
from matplotlib.figure import Figure

matplotlib.rcParams["font.family"] = ["Microsoft YaHei", "SimHei", "sans-serif"]
matplotlib.rcParams["axes.unicode_minus"] = False

DEFAULT_CSV = str(Path(__file__).resolve().parent.parent / "logs" / "easicam-monitor-v2.csv")
POLL_MS = 500

# CSV header: ts,pid,uptime_s,cpu_pct,ws_mb,priv_mb,handles,gdi,user,gpu_proc,gpu_sys,gpu_ded,gpu_sha,note


class DataStore:
    """Thread-safe incremental tail reader for the monitor CSV."""

    def __init__(self, path):
        self.path = path
        self.lock = threading.Lock()
        self.rows = []      # sample dicts
        self.events = []    # (datetime, note)
        self.offset = 0

    def poll(self):
        """Read newly appended lines; returns count of new lines consumed."""
        try:
            size = os.path.getsize(self.path)
        except OSError:
            return 0
        added = 0
        with self.lock:
            if size < self.offset:
                self.rows.clear()
                self.events.clear()
                self.offset = 0
            try:
                with open(self.path, "rb") as f:
                    f.seek(self.offset)
                    chunk = f.read()
            except OSError:
                return 0
            if not chunk:
                return 0
            # keep only complete lines (ending with \n)
            cut = chunk.rfind(b"\n")
            if cut < 0:
                return 0
            text = chunk[: cut + 1].decode("ascii", errors="replace")
            self.offset += cut + 1
            for line in text.splitlines():
                line = line.strip("\r").strip()
                if not line:
                    continue
                parts = line.split(",")
                if len(parts) < 14 or parts[0] == "ts":
                    continue
                note = ",".join(parts[13:]).strip()
                try:
                    t = dt.datetime.strptime(parts[0], "%Y-%m-%d %H:%M:%S.%f")
                except ValueError:
                    continue
                if note:
                    self.events.append((t, note))
                    continue
                try:
                    self.rows.append({
                        "ts": t,
                        "pid": int(parts[1]),
                        "uptime": float(parts[2]),
                        "cpu": float(parts[3]),
                        "ws": float(parts[4]),
                        "priv": float(parts[5]),
                        "handles": int(parts[6]),
                        "gdi": int(parts[7]),
                        "user": int(parts[8]),
                    })
                except ValueError:
                    continue
                added += 1
        return added


def series(rows, key):
    """Return (xs, ys) with NaN breaks whenever pid changes."""
    xs, ys = [], []
    prev_pid = None
    for r in rows:
        if prev_pid is not None and r["pid"] != prev_pid:
            xs.append(r["ts"])
            ys.append(float("nan"))
        prev_pid = r["pid"]
        xs.append(r["ts"])
        ys.append(r[key])
    return xs, ys


def compress_events(events):
    """Collapse repeated identical notes (e.g. 'no EasiCamera' spam) to one mark."""
    out = []
    last_note, last_t = None, None
    for t, note in events:
        if note == last_note and (t - last_t).total_seconds() < 15:
            last_t = t
            continue
        out.append((t, note))
        last_note, last_t = note, t
    return out


class ViewerApp:
    def __init__(self, root, store):
        self.root = root
        self.store = store
        self.paused = tk.BooleanVar(value=False)

        root.title("EasiCam Monitor Viewer - " + os.path.basename(store.path))
        root.geometry("1280x860")

        fig = Figure(figsize=(12.8, 8.0), dpi=100)
        fig.subplots_adjust(left=0.06, right=0.985, top=0.94, bottom=0.07,
                            hspace=0.32, wspace=0.22)
        self.fig = fig
        self.ax_h = fig.add_subplot(2, 2, 1)
        self.ax_c = fig.add_subplot(2, 2, 2)
        self.ax_m = fig.add_subplot(2, 2, 3)
        self.ax_o = fig.add_subplot(2, 2, 4)

        (self.ln_h,) = self.ax_h.plot([], [], color="#1f77b4", lw=1.2, label="handles")
        (self.ln_c,) = self.ax_c.plot([], [], color="#2ca02c", lw=1.2, label="cpu %")
        (self.ln_ws,) = self.ax_m.plot([], [], color="#ff7f0e", lw=1.2, label="ws MB")
        (self.ln_pv,) = self.ax_m.plot([], [], color="#d62728", lw=1.2, label="priv MB")
        (self.ln_g,) = self.ax_o.plot([], [], color="#9467bd", lw=1.2, label="gdi")
        (self.ln_u,) = self.ax_o.plot([], [], color="#17becf", lw=1.2, label="user")

        self._style(self.ax_h, "Handles (patch check)", "count")
        self._style(self.ax_c, "CPU", "%")
        self._style(self.ax_m, "Memory", "MB")
        self._style(self.ax_o, "GDI / USER objects", "count")
        self.ax_m.legend(loc="upper left", fontsize=8)
        self.ax_o.legend(loc="upper left", fontsize=8)

        canvas = FigureCanvasTkAgg(fig, master=root)
        canvas.draw()
        canvas.get_tk_widget().pack(side=tk.TOP, fill=tk.BOTH, expand=1)
        self.canvas = canvas
        self.toolbar = NavigationToolbar2Tk(canvas, root)
        self.toolbar.update()

        bar = ttk.Frame(root)
        bar.pack(side=tk.BOTTOM, fill=tk.X)
        ttk.Checkbutton(bar, text="暂停刷新", variable=self.paused).pack(side=tk.LEFT, padx=8, pady=4)
        self.status = ttk.Label(bar, text="loading...")
        self.status.pack(side=tk.LEFT, padx=8)

        self.first_draw = True
        root.after(300, self.refresh)

    @staticmethod
    def _style(ax, title, ylabel):
        ax.set_title(title, fontsize=10)
        ax.set_ylabel(ylabel, fontsize=9)
        ax.grid(True, which="both", alpha=0.3)
        ax.xaxis.set_major_formatter(mdates.DateFormatter("%H:%M:%S"))
        ax.tick_params(labelsize=8)
        for lb in ax.get_xticklabels():
            lb.set_rotation(20)
            lb.set_ha("right")

    def _autoscale_if_idle(self, ax):
        toolbar = getattr(self, "toolbar", None)
        if toolbar is not None and toolbar.mode:
            return
        ax.relim()
        ax.autoscale_view()

    def refresh(self):
        try:
            if not self.paused.get():
                self.store.poll()
                self.redraw()
        finally:
            self.root.after(POLL_MS, self.refresh)

    def redraw(self):
        rows = self.store.rows
        xs_h, ys_h = series(rows, "handles")
        self.ln_h.set_data(xs_h, ys_h)
        self.ln_c.set_data(*series(rows, "cpu"))
        self.ln_ws.set_data(*series(rows, "ws"))
        self.ln_pv.set_data(*series(rows, "priv"))
        self.ln_g.set_data(*series(rows, "gdi"))
        self.ln_u.set_data(*series(rows, "user"))

        ax = self.ax_h
        while ax.texts:
            ax.texts[0].remove()
        for line in list(ax.lines):
            if line is not self.ln_h:
                line.remove()
        for t, note in compress_events(self.store.events):
            ax.axvline(t, color="red", ls="--", lw=0.8, alpha=0.7)
            ax.text(t, 1.02, note[:38], transform=ax.get_xaxis_transform(),
                    rotation=90, fontsize=7, color="red", va="bottom", ha="right")

        if rows:
            for a in (self.ax_h, self.ax_c, self.ax_m, self.ax_o):
                a.set_xlim(rows[0]["ts"], rows[-1]["ts"])
            self._autoscale_if_idle(self.ax_h)
            self._autoscale_if_idle(self.ax_c)
            self._autoscale_if_idle(self.ax_m)
            self._autoscale_if_idle(self.ax_o)
            last = rows[-1]
            self.status.config(text=(
                "PID %s  uptime %.0fs  handles %d  cpu %.1f%%  ws %.0fMB priv %.0fMB"
                "  gdi %d user %d  |  samples %d  events %d"
                % (last["pid"], last["uptime"], last["handles"], last["cpu"],
                   last["ws"], last["priv"], last["gdi"], last["user"],
                   len(rows), len(self.store.events))))
        self.canvas.draw_idle()


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_CSV
    if not os.path.exists(path):
        print("CSV not found:", path)
        sys.exit(1)
    store = DataStore(path)
    store.poll()
    root = tk.Tk()
    ViewerApp(root, store)
    root.mainloop()


if __name__ == "__main__":
    main()
