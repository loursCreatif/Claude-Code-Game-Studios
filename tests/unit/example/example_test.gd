# Example unit test — proves the GdUnit4 framework is wired up.
# Remove this file once the first real system test is written.
# Run: godot --headless --script tests/gdunit4_runner.gd

extends GdUnitTestSuite

func test_arithmetic_identity_holds() -> void:
	assert_int(2 + 2).is_equal(4)

func test_string_equality_is_deterministic() -> void:
	var action: StringName = &"jump"
	assert_str(String(action)).is_equal("jump")

func test_vector3_zero_is_origin() -> void:
	var v := Vector3.ZERO
	assert_float(v.length()).is_equal(0.0)
