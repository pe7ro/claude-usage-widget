// SPDX-FileCopyrightText: 2026 pe7ro
// SPDX-License-Identifier: MIT
// Text for the widget. Pure functions over the report that `claude-usage report --json`
// prints; times are epoch seconds, `now` is passed in so every view agrees on it.
.pragma library

// Countdown / age: "4d 3h", "2h 13m", "47m", "<1m"
function duration(seconds) {
    if (seconds === null || seconds === undefined || isNaN(seconds))
        return ""
    var s = Math.max(0, Math.floor(seconds))
    var d = Math.floor(s / 86400), h = Math.floor(s % 86400 / 3600), m = Math.floor(s % 3600 / 60)
    if (d > 0) return d + "d " + h + "h"
    if (h > 0) return h + "h " + m + "m"
    if (m > 0) return m + "m"
    return "<1m"
}

// A clock time, with the weekday when it isn't today: "16:40", "Mon 09:00"
function when(ts, now) {
    if (ts === null || ts === undefined)
        return "?"
    var d = new Date(ts * 1000)
    var today = new Date(now * 1000)
    if (d.toDateString() === today.toDateString())
        return Qt.formatTime(d, "HH:mm")
    return Qt.formatDateTime(d, "ddd HH:mm")
}

function ago(ts, now) {
    if (ts === null || ts === undefined)
        return ""
    return now - ts < 60 ? "just now" : duration(now - ts) + " ago"
}

function percent(p) {
    return Math.round(p) + "%"
}

// "812k", "1M", "1.5M"
function tokens(n) {
    if (n === null || n === undefined)
        return "?"
    if (n >= 1e6) {
        var m = n / 1e6
        return (m >= 10 || Math.abs(m - Math.round(m)) < 0.05 ? Math.round(m) : m.toFixed(1)) + "M"
    }
    if (n >= 1e3)
        return Math.round(n / 1e3) + "k"
    return String(Math.round(n))
}

// The window has reset since the reading was taken: its usage is unknown until the next
// Claude Code response, so it is shown as reset, never as a made-up 0%.
function isReset(limit, now) {
    return !!limit && (limit.expired || (limit.resets_at !== null && limit.resets_at <= now))
}

// "none" | "normal" | "warn" | "critical"
function level(limit, now, warnAt, criticalAt) {
    if (!limit || isReset(limit, now))
        return "none"
    var p = limit.used_percentage
    return p >= criticalAt ? "critical" : p >= warnAt ? "warn" : "normal"
}

// The two panel lines: large percentage over small time-left.
function compactLines(limit, now) {
    if (!limit)
        return { top: "—", bottom: "no data" }
    if (isReset(limit, now))
        return { top: "—", bottom: "reset" }
    return {
        top: percent(limit.used_percentage),
        bottom: limit.resets_at !== null ? duration(limit.resets_at - now) : ""
    }
}

function limitValue(limit, now) {
    if (!limit) return "—"
    if (isReset(limit, now)) return "reset"
    return percent(limit.used_percentage)
}

function limitDetail(limit, now) {
    if (!limit)
        return "no reading yet"
    if (isReset(limit, now))
        return "reset at " + when(limit.resets_at, now) + " · no reading since"
    var parts = []
    if (limit.resets_at !== null)
        parts.push("resets " + when(limit.resets_at, now) + " · in " + duration(limit.resets_at - now))
    parts.push("as of " + when(limit.as_of, now))
    return parts.join(" · ")
}

function limitSummary(name, limit, now) {
    if (!limit)
        return name + ": no reading yet"
    if (isReset(limit, now))
        return name + ": reset at " + when(limit.resets_at, now)
    var text = name + ": " + percent(limit.used_percentage) + " used"
    if (limit.resets_at !== null)
        text += ", resets " + when(limit.resets_at, now) + " (in " + duration(limit.resets_at - now) + ")"
    return text
}

function tooltip(report, now, error) {
    if (error)
        return "Error: " + error
    var limits = report && report.limits ? report.limits : {}
    var lines = [limitSummary("5-hour", limits.five_hour, now), limitSummary("7-day", limits.seven_day, now)]
    if (limits.five_hour && !isReset(limits.five_hour, now))
        lines.push("as of " + when(limits.five_hour.as_of, now))
    return lines.join("\n")
}

function contextMeasured(ctx) {
    return !!ctx && ctx.used_percentage !== null && ctx.used_percentage !== undefined
}

// The share of the context window in use, the large number on a session row.
function contextValue(ctx) {
    return contextMeasured(ctx) ? percent(ctx.used_percentage) : "—"
}

// Same scale as level() for the plan limits.
function contextLevel(ctx, warnAt, criticalAt) {
    if (!contextMeasured(ctx))
        return "none"
    var p = ctx.used_percentage
    return p >= criticalAt ? "critical" : p >= warnAt ? "warn" : "normal"
}

// No percentage here: the row already shows the used share large.
function contextLine(ctx) {
    if (!ctx || ctx.free_tokens === null || ctx.free_tokens === undefined)
        return "context not measured yet"
    return tokens(ctx.free_tokens) + " free of " + tokens(ctx.size)
}

function sessionState(session, now) {
    if (session.state === "ended")
        return "ended " + ago(session.ended_at, now)
    var age = ago(session.last_response_at, now)
    return session.state === "idle" ? "idle · " + age : age
}

function sessionDetail(session) {
    var parts = [contextLine(session.context)]
    if (session.cost_usd)  // null before the first response, 0 until then too
        parts.push("≈ $" + session.cost_usd.toFixed(2))
    if (session.cwd_display)
        parts.push(session.cwd_display)
    return parts.join(" · ")
}
