Config = {}

-- Milliseconds between zone location polls.
-- Players cannot cross a district boundary faster than this matters —
-- district boundaries are large and weather transitions are gradual.
-- Safe to increase if performance is a concern.
Config.ZonePollInterval = 5000