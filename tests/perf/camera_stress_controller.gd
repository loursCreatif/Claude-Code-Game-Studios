# Camera stress scene controller — used by story-012 perf integration test.
# Provides 3 enemy stubs (Node3D, no logic) + wall-right stub for entity count context.
# NOT a self-running test — scene is loaded + driven by
# tests/integration/camera/story_012_perf_instrumentation_test.gd via GdUnit4.
# Headless-safe : no GUI, no render output checks, no OS.alert() paths.

extends Node3D
