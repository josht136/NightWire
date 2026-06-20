#!/usr/bin/env python3
"""Ping tracker with live matplotlib chart and SQLite history."""

import sqlite3
from pathlib import Path
from time import sleep

import matplotlib.pyplot as plt
import ping3

DB_PATH = Path(__file__).resolve().parent / "ping_times.db"
POLL_INTERVAL_SEC = 10
CHART_HISTORY_LIMIT = 10


def setup_db() -> None:
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute(
        """
        CREATE TABLE IF NOT EXISTS ping_data (
            address TEXT,
            timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
            response_time REAL
        )
        """
    )
    conn.commit()
    conn.close()


def ping_address(address: str) -> float:
    try:
        latency = ping3.ping(address, timeout=1)
        if latency is None or latency is False:
            return float("inf")
        return latency * 1000
    except Exception as exc:
        print(f"Error pinging {address}: {exc}")
        return float("inf")


def store_ping(address: str, response_time_ms: float) -> None:
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute(
        "INSERT INTO ping_data (address, response_time) VALUES (?, ?)",
        (address, response_time_ms),
    )
    conn.commit()
    conn.close()


def get_latest_latencies(address: str, limit: int = CHART_HISTORY_LIMIT) -> list[tuple[str, float]]:
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute(
        """
        SELECT timestamp, response_time FROM ping_data
        WHERE address = ? ORDER BY timestamp DESC LIMIT ?
        """,
        (address, limit),
    )
    rows = list(reversed(cursor.fetchall()))
    conn.close()
    return rows


def main_loop(addresses: list[str]) -> None:
    setup_db()
    plt.ion()

    while True:
        for address in addresses:
            latency_ms = ping_address(address)
            store_ping(address, latency_ms)
            display = "timeout" if latency_ms == float("inf") else f"{latency_ms:.1f} ms"
            print(f"{address}: {display}")

        plt.clf()
        plt.figure(1, figsize=(10, 6))

        for address in addresses:
            latencies = get_latest_latencies(address)
            if not latencies:
                continue
            times = [row[0] for row in latencies]
            values = [row[1] for row in latencies]
            plt.plot(times, values, marker="o", label=address)

        plt.title("Ping Tracker")
        plt.xlabel("Time")
        plt.ylabel("Response Time (ms)")
        plt.legend()
        plt.grid(True)
        plt.xticks(rotation=45)
        plt.tight_layout()
        plt.draw()
        plt.pause(POLL_INTERVAL_SEC)


if __name__ == "__main__":
    addresses_to_track = ["8.8.8.8", "1.1.1.1"]
    main_loop(addresses_to_track)
