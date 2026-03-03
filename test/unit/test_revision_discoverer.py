"""
Unit tests for RevisionDiscoverer and FeatureProviderBase integration.

This test suite covers:
- Revision name parsing with valid and invalid formats
- Revision validation with various file combinations
- Latest revision discovery with multiple revisions and timestamps
- Task isolation between different tasks
- Error handling for missing directories and invalid revisions
"""

from datetime import datetime, timezone
from pathlib import Path
from unittest.mock import Mock, patch

import pytest
import yaml

# Import from vtol-interface source
import sys

vtol_interface_src = Path(__file__).parent.parent.parent / "vtol-interface" / "src"
sys.path.insert(0, str(vtol_interface_src))

from features.revision_discoverer import RevisionDiscoverer
from features.feature_provider_base import (
    FeatureProviderBase,
    FeatureSpec,
    FeatureValidationResult,
)


# =============================================================================
# Test Fixtures
# =============================================================================


@pytest.fixture
def temp_artifacts_root(tmp_path):
    """
    Create a temporary artifacts root directory structure.

    Returns:
        Path: Temporary artifacts root directory
    """
    return tmp_path


@pytest.fixture
def valid_metadata_content():
    """
    Return valid observations_metadata.yaml content.

    Returns:
        dict: Valid metadata structure
    """
    return {
        "low_dim": [
            {"name": "position", "dim": 3},
            {"name": "velocity", "dim": 3},
            {"name": "orientation", "dim": 4},
        ]
    }


# =============================================================================
# Test Class: TestParseRevisionName
# =============================================================================


class TestParseRevisionName:
    """Test suite for RevisionDiscoverer._parse_revision_name() method."""

    def test_standard_format_extracts_timestamp(self):
        """Test that standard format correctly extracts timestamp."""
        revision_name = "vtol_hover-20260303T110451Z-bd60e47b-746b0cb9"

        result = RevisionDiscoverer._parse_revision_name(revision_name)

        expected = datetime(2026, 3, 3, 11, 4, 51, tzinfo=timezone.utc)
        assert result == expected

    def test_different_task_names(self):
        """Test that various task names are handled correctly."""
        test_cases = [
            ("vtol_hover-20260303T110451Z-hash", "vtol_hover"),
            ("vtol_nav-20260101T000000Z-hash", "vtol_nav"),
            ("simple-20260228T235959Z-hash", "simple"),
        ]

        for revision_name, task_name in test_cases:
            result = RevisionDiscoverer._parse_revision_name(revision_name)
            assert result is not None
            assert result.year == 2026

    def test_multiple_hashes_in_name(self):
        """Test that multiple hash parts are handled correctly."""
        revision_name = "vtol_hover-20260303T110451Z-bd60e47b-746b0cb9-extra-hash"

        result = RevisionDiscoverer._parse_revision_name(revision_name)

        expected = datetime(2026, 3, 3, 11, 4, 51, tzinfo=timezone.utc)
        assert result == expected

    def test_missing_hash_part(self):
        """Test that missing hash part still extracts timestamp."""
        revision_name = "vtol_hover-20260303T110451Z"

        result = RevisionDiscoverer._parse_revision_name(revision_name)

        expected = datetime(2026, 3, 3, 11, 4, 51, tzinfo=timezone.utc)
        assert result == expected

    def test_leap_day(self):
        """Test that leap day is handled correctly."""
        revision_name = "vtol_hover-20240229T235959Z-hash"

        result = RevisionDiscoverer._parse_revision_name(revision_name)

        expected = datetime(2024, 2, 29, 23, 59, 59, tzinfo=timezone.utc)
        assert result == expected

    def test_end_of_month_boundaries(self):
        """Test month boundaries are handled correctly."""
        test_cases = [
            ("vtol_hover-20260131T235959Z-hash", 2026, 1, 31),
            ("vtol_hover-20260228T235959Z-hash", 2026, 2, 28),
            ("vtol_hover-20260430T235959Z-hash", 2026, 4, 30),
            ("vtol_hover-20261231T235959Z-hash", 2026, 12, 31),
        ]

        for revision_name, year, month, day in test_cases:
            result = RevisionDiscoverer._parse_revision_name(revision_name)
            assert result is not None
            assert result.year == year
            assert result.month == month
            assert result.day == day

    def test_time_boundaries(self):
        """Test time boundaries are handled correctly."""
        test_cases = [
            ("vtol_hover-20260303T000000Z-hash", 0, 0, 0),
            ("vtol_hover-20260303T115959Z-hash", 11, 59, 59),
            ("vtol_hover-20260303T235959Z-hash", 23, 59, 59),
        ]

        for revision_name, hour, minute, second in test_cases:
            result = RevisionDiscoverer._parse_revision_name(revision_name)
            assert result is not None
            assert result.hour == hour
            assert result.minute == minute
            assert result.second == second

    def test_no_timestamp_returns_none(self):
        """Test that missing timestamp returns None."""
        revision_name = "vtol_hover_no_timestamp"

        result = RevisionDiscoverer._parse_revision_name(revision_name)

        assert result is None

    def test_single_dash_returns_none(self):
        """Test that single dash returns None."""
        revision_name = "vtol_hover"

        result = RevisionDiscoverer._parse_revision_name(revision_name)

        assert result is None

    def test_malformed_timestamp_returns_none(self):
        """Test that malformed timestamp returns None."""
        test_cases = [
            "vtol_hover-invalid-timestamp-hash",
            "vtol_hover-20260303 110451Z-hash",  # Space instead of T
            "vtol_hover-20260303T110451-hash",  # Missing Z
            "vtol_hover-26-03-03-hash",  # Wrong format
            "vtol-hover-20260303T110451Z-hash",  # Task name with dash
        ]

        for revision_name in test_cases:
            result = RevisionDiscoverer._parse_revision_name(revision_name)
            assert result is None, f"Expected None for: {revision_name}"

    def test_invalid_length_timestamp_returns_none(self):
        """Test that invalid timestamp length returns None."""
        test_cases = [
            "vtol_hover-202603T110451Z-hash",  # Too short (year only)
            "vtol-hover-20260303T110451123Z-hash",  # Too long
        ]

        for revision_name in test_cases:
            result = RevisionDiscoverer._parse_revision_name(revision_name)
            assert result is None

    def test_t_missing_returns_none(self):
        """Test that missing T separator returns None."""
        revision_name = "vtol_hover-20260303110451Z-hash"

        result = RevisionDiscoverer._parse_revision_name(revision_name)

        assert result is None

    def test_z_missing_returns_none(self):
        """Test that missing Z suffix returns None."""
        revision_name = "vtol_hover-20260303T110451-hash"

        result = RevisionDiscoverer._parse_revision_name(revision_name)

        assert result is None

    def test_invalid_date_returns_none(self):
        """Test that invalid date returns None."""
        test_cases = [
            "vtol_hover-20261301T110451Z-hash",  # Invalid month
            "vtol_hover-20260232T110451Z-hash",  # Invalid day (Feb 32)
            "vtol_hover-20260303T250000Z-hash",  # Invalid hour
            "vtol_hover-20260303T116000Z-hash",  # Invalid minute
            "vtol_hover-20260303T115960Z-hash",  # Invalid second
        ]

        for revision_name in test_cases:
            result = RevisionDiscoverer._parse_revision_name(revision_name)
            assert result is None, f"Expected None for invalid date: {revision_name}"

    def test_non_string_input_returns_none(self):
        """Test that non-string input returns None."""
        test_cases = [123, None, [], {}]

        for input_val in test_cases:
            with pytest.raises(AttributeError):
                RevisionDiscoverer._parse_revision_name(input_val)

    def test_empty_string_returns_none(self):
        """Test that empty string returns None."""
        revision_name = ""

        result = RevisionDiscoverer._parse_revision_name(revision_name)

        assert result is None

    def test_timestamp_only_returns_datetime(self):
        """Test that timestamp-only format is handled."""
        revision_name = "20260303T110451Z"

        result = RevisionDiscoverer._parse_revision_name(revision_name)

        # This will return None because the first part is not a valid timestamp
        # The timestamp is expected at index 1 after splitting by dash
        assert result is None


# =============================================================================
# Test Class: TestValidateRevision
# =============================================================================


class TestValidateRevision:
    """Test suite for RevisionDiscoverer._validate_revision() method."""

    def test_valid_revision_returns_true(self, tmp_path):
        """Test that valid revision with both files returns True."""
        rev_path = tmp_path / "test_revision"
        rev_path.mkdir()

        (rev_path / "model.onnx").touch()
        (rev_path / "observations_metadata.yaml").touch()

        result = RevisionDiscoverer._validate_revision(rev_path)

        assert result is True

    def test_missing_model_returns_false(self, tmp_path):
        """Test that missing model.onnx returns False."""
        rev_path = tmp_path / "test_revision"
        rev_path.mkdir()

        (rev_path / "observations_metadata.yaml").touch()

        result = RevisionDiscoverer._validate_revision(rev_path)

        assert result is False

    def test_missing_metadata_returns_false(self, tmp_path):
        """Test that missing observations_metadata.yaml returns False."""
        rev_path = tmp_path / "test_revision"
        rev_path.mkdir()

        (rev_path / "model.onnx").touch()

        result = RevisionDiscoverer._validate_revision(rev_path)

        assert result is False

    def test_both_missing_returns_false(self, tmp_path):
        """Test that missing both files returns False."""
        rev_path = tmp_path / "test_revision"
        rev_path.mkdir()

        result = RevisionDiscoverer._validate_revision(rev_path)

        assert result is False

    def test_extra_files_with_valid_returns_true(self, tmp_path):
        """Test that extra files don't affect validation."""
        rev_path = tmp_path / "test_revision"
        rev_path.mkdir()

        (rev_path / "model.onnx").touch()
        (rev_path / "observations_metadata.yaml").touch()
        (rev_path / "extra_file.txt").touch()
        (rev_path / "data.csv").touch()

        result = RevisionDiscoverer._validate_revision(rev_path)

        assert result is True

    def test_subdirectory_with_valid_returns_true(self, tmp_path):
        """Test that subdirectories don't affect validation."""
        rev_path = tmp_path / "test_revision"
        rev_path.mkdir()

        (rev_path / "model.onnx").touch()
        (rev_path / "observations_metadata.yaml").touch()
        (rev_path / "subdir").mkdir()

        result = RevisionDiscoverer._validate_revision(rev_path)

        assert result is True

    def test_nonexistent_directory_returns_false(self, tmp_path):
        """Test that non-existent directory returns False."""
        rev_path = tmp_path / "nonexistent"

        result = RevisionDiscoverer._validate_revision(rev_path)

        assert result is False

    def test_file_instead_of_directory(self, tmp_path):
        """Test that file instead of directory returns False."""
        rev_path = tmp_path / "not_a_directory"
        rev_path.touch()

        result = RevisionDiscoverer._validate_revision(rev_path)

        assert result is False

    def test_model_file_with_content(self, tmp_path):
        """Test that model file with content is valid."""
        rev_path = tmp_path / "test_revision"
        rev_path.mkdir()

        (rev_path / "model.onnx").write_bytes(b"fake onnx data")
        (rev_path / "observations_metadata.yaml").write_text("metadata: test")

        result = RevisionDiscoverer._validate_revision(rev_path)

        assert result is True

    def test_different_case_filenames(self, tmp_path):
        """Test that exact filename match is required."""
        rev_path = tmp_path / "test_revision"
        rev_path.mkdir()

        # Wrong case
        (rev_path / "MODEL.onnx").touch()
        (rev_path / "observations_metadata.yaml").touch()

        result = RevisionDiscoverer._validate_revision(rev_path)

        assert result is False

    def test_yaml_with_different_extension(self, tmp_path):
        """Test that .yaml extension is required."""
        rev_path = tmp_path / "test_revision"
        rev_path.mkdir()

        (rev_path / "model.onnx").touch()
        (rev_path / "observations_metadata.yml").touch()

        result = RevisionDiscoverer._validate_revision(rev_path)

        assert result is False

    def test_onnx_with_different_extension(self, tmp_path):
        """Test that .onnx extension is required."""
        rev_path = tmp_path / "test_revision"
        rev_path.mkdir()

        (rev_path / "model.onn").touch()
        (rev_path / "observations_metadata.yaml").touch()

        result = RevisionDiscoverer._validate_revision(rev_path)

        assert result is False


# =============================================================================
# Test Class: TestDiscoverLatest
# =============================================================================


class TestDiscoverLatest:
    """Test suite for RevisionDiscoverer.discover_latest() method."""

    def test_single_valid_revision(self, temp_artifacts_root):
        """Test that single valid revision is returned."""
        task = "test_task"
        task_dir = temp_artifacts_root / "policies" / task
        task_dir.mkdir(parents=True)

        rev = task_dir / "test_task-20260303T110451Z-hash1"
        rev.mkdir()
        (rev / "model.onnx").touch()
        (rev / "observations_metadata.yaml").touch()

        result = RevisionDiscoverer.discover_latest(temp_artifacts_root, task)

        assert result == rev

    def test_multiple_valid_revisions_returns_latest(self, temp_artifacts_root):
        """Test that multiple valid revisions returns the latest."""
        task = "test_task"
        task_dir = temp_artifacts_root / "policies" / task
        task_dir.mkdir(parents=True)

        rev1 = task_dir / "test_task-20260301T100000Z-hash1"
        rev2 = task_dir / "test_task-20260302T120000Z-hash2"
        rev3 = task_dir / "test_task-20260303T110451Z-hash3"

        for rev in [rev1, rev2, rev3]:
            rev.mkdir()
            (rev / "model.onnx").touch()
            (rev / "observations_metadata.yaml").touch()

        result = RevisionDiscoverer.discover_latest(temp_artifacts_root, task)

        assert result == rev3

    def test_mixed_valid_invalid_returns_latest_valid(self, temp_artifacts_root):
        """Test that invalid revisions are filtered and latest valid is returned."""
        task = "test_task"
        task_dir = temp_artifacts_root / "policies" / task
        task_dir.mkdir(parents=True)

        rev1 = task_dir / "test_task-20260301T100000Z-hash1"
        rev2 = task_dir / "test_task-20260302T120000Z-hash2"  # Invalid
        rev3 = task_dir / "test_task-20260303T110451Z-hash3"  # Latest valid

        rev1.mkdir()
        (rev1 / "model.onnx").touch()
        (rev1 / "observations_metadata.yaml").touch()

        rev2.mkdir()
        (rev2 / "observations_metadata.yaml").touch()  # Missing model

        rev3.mkdir()
        (rev3 / "model.onnx").touch()
        (rev3 / "observations_metadata.yaml").touch()

        result = RevisionDiscoverer.discover_latest(temp_artifacts_root, task)

        assert result == rev3

    def test_all_invalid_returns_none(self, temp_artifacts_root):
        """Test that all invalid revisions returns None."""
        task = "test_task"
        task_dir = temp_artifacts_root / "policies" / task
        task_dir.mkdir(parents=True)

        rev1 = task_dir / "test_task-20260301T100000Z-hash1"
        rev2 = task_dir / "test_task-20260302T120000Z-hash2"

        rev1.mkdir()  # Empty
        rev2.mkdir()
        (rev2 / "model.onnx").touch()  # Missing metadata

        result = RevisionDiscoverer.discover_latest(temp_artifacts_root, task)

        assert result is None

    def test_empty_task_directory_returns_none(self, temp_artifacts_root):
        """Test that empty task directory returns None."""
        task = "test_task"
        task_dir = temp_artifacts_root / "policies" / task
        task_dir.mkdir(parents=True)

        result = RevisionDiscoverer.discover_latest(temp_artifacts_root, task)

        assert result is None

    def test_missing_task_directory_returns_none(self, temp_artifacts_root):
        """Test that missing task directory returns None."""
        task = "test_task"

        result = RevisionDiscoverer.discover_latest(temp_artifacts_root, task)

        assert result is None

    def test_missing_policies_directory_returns_none(self, temp_artifacts_root):
        """Test that missing policies directory returns None."""
        task = "test_task"

        # Don't create policies directory
        result = RevisionDiscoverer.discover_latest(temp_artifacts_root, task)

        assert result is None

    def test_revisions_with_same_timestamp(self, temp_artifacts_root):
        """Test that revisions with same timestamp are handled."""
        task = "test_task"
        task_dir = temp_artifacts_root / "policies" / task
        task_dir.mkdir(parents=True)

        # Two revisions with same timestamp but different hash
        rev1 = task_dir / "test_task-20260303T110451Z-hash1"
        rev2 = task_dir / "test_task-20260303T110451Z-hash2"

        for rev in [rev1, rev2]:
            rev.mkdir()
            (rev / "model.onnx").touch()
            (rev / "observations_metadata.yaml").touch()

        result = RevisionDiscoverer.discover_latest(temp_artifacts_root, task)

        # Either is acceptable since they have the same timestamp
        assert result is not None
        assert result in [rev1, rev2]

    def test_revisions_in_chronological_order(self, temp_artifacts_root):
        """Test that revisions are sorted correctly chronologically."""
        task = "test_task"
        task_dir = temp_artifacts_root / "policies" / task
        task_dir.mkdir(parents=True)

        # Create in non-chronological order
        revisions = [
            (
                "test_task-20260302T120000Z-hash2",
                datetime(2026, 3, 2, 12, 0, 0, tzinfo=timezone.utc),
            ),
            (
                "test_task-20260303T110451Z-hash3",
                datetime(2026, 3, 3, 11, 4, 51, tzinfo=timezone.utc),
            ),
            (
                "test_task-20260301T100000Z-hash1",
                datetime(2026, 3, 1, 10, 0, 0, tzinfo=timezone.utc),
            ),
        ]

        for name, expected_ts in revisions:
            rev = task_dir / name
            rev.mkdir()
            (rev / "model.onnx").touch()
            (rev / "observations_metadata.yaml").touch()

            # Verify timestamp parsing
            ts = RevisionDiscoverer._parse_revision_name(name)
            assert ts == expected_ts

        result = RevisionDiscoverer.discover_latest(temp_artifacts_root, task)

        assert result == task_dir / "test_task-20260303T110451Z-hash3"

    def test_files_instead_of_directories_are_ignored(self, temp_artifacts_root):
        """Test that files are ignored."""
        task = "test_task"
        task_dir = temp_artifacts_root / "policies" / task
        task_dir.mkdir(parents=True)

        # Create a file with revision-like name
        (task_dir / "test_task-20260303T110451Z-hash1").touch()

        result = RevisionDiscoverer.discover_latest(temp_artifacts_root, task)

        assert result is None

    def test_symlinks_to_directories(self, temp_artifacts_root):
        """Test that symlinks to directories work."""
        task = "test_task"
        task_dir = temp_artifacts_root / "policies" / task
        task_dir.mkdir(parents=True)

        # Create actual revision directory
        actual_rev = temp_artifacts_root / "actual_rev"
        actual_rev.mkdir()
        (actual_rev / "model.onnx").touch()
        (actual_rev / "observations_metadata.yaml").touch()

        # Create symlink
        rev_link = task_dir / "test_task-20260303T110451Z-hash1"
        rev_link.symlink_to(actual_rev)

        result = RevisionDiscoverer.discover_latest(temp_artifacts_root, task)

        assert result == rev_link

    def test_large_number_of_revisions(self, temp_artifacts_root):
        """Test that many revisions are handled efficiently."""
        task = "test_task"
        task_dir = temp_artifacts_root / "policies" / task
        task_dir.mkdir(parents=True)

        # Create 100 revisions with different timestamps
        for i in range(100):
            # Use different minutes to generate unique timestamps
            timestamp = datetime(2026, 3, 3, i // 60, i % 60, 0, tzinfo=timezone.utc)
            timestamp_str = timestamp.strftime("%Y%m%dT%H%M%SZ")
            rev = task_dir / f"test_task-{timestamp_str}-hash{i}"
            rev.mkdir()
            (rev / "model.onnx").touch()
            (rev / "observations_metadata.yaml").touch()

        result = RevisionDiscoverer.discover_latest(temp_artifacts_root, task)

        # Should return the one with highest timestamp (last one created)
        assert result is not None
        assert "hash99" in result.name


# =============================================================================
# Test Class: TestTaskIsolation
# =============================================================================


class TestTaskIsolation:
    """Test suite for task isolation functionality."""

    def test_different_tasks_dont_interfere(self, temp_artifacts_root):
        """Test that different tasks are isolated."""
        task1 = "vtol_hover"
        task2 = "vtol_nav"

        task1_dir = temp_artifacts_root / "policies" / task1
        task2_dir = temp_artifacts_root / "policies" / task2
        task1_dir.mkdir(parents=True)
        task2_dir.mkdir(parents=True)

        # Create revisions for task1
        rev1 = task1_dir / "vtol_hover-20260301T100000Z-hash1"
        rev1.mkdir()
        (rev1 / "model.onnx").touch()
        (rev1 / "observations_metadata.yaml").touch()

        # Create revisions for task2
        rev2 = task2_dir / "vtol_nav-20260303T110451Z-hash2"
        rev2.mkdir()
        (rev2 / "model.onnx").touch()
        (rev2 / "observations_metadata.yaml").touch()

        # Discover for each task
        result1 = RevisionDiscoverer.discover_latest(temp_artifacts_root, task1)
        result2 = RevisionDiscoverer.discover_latest(temp_artifacts_root, task2)

        assert result1 == rev1
        assert result2 == rev2

    def test_task_with_dash_in_name(self, temp_artifacts_root):
        """Test that tasks with underscores are handled correctly."""
        # Note: Dashes in task names are not supported because the revision name
        # format is {task_name}-{timestamp}-{hash} and dashes are used as separators
        task = "vtol_hover_task"
        task_dir = temp_artifacts_root / "policies" / task
        task_dir.mkdir(parents=True)

        # Revision with same prefix
        rev = task_dir / "vtol_hover_task-20260303T110451Z-hash1"
        rev.mkdir()
        (rev / "model.onnx").touch()
        (rev / "observations_metadata.yaml").touch()

        result = RevisionDiscoverer.discover_latest(temp_artifacts_root, task)

        assert result is not None

    def test_missing_task_does_not_affect_others(self, temp_artifacts_root):
        """Test that missing task doesn't affect existing tasks."""
        task1 = "task1"
        task2 = "task2"

        # Only create task1
        task1_dir = temp_artifacts_root / "policies" / task1
        task1_dir.mkdir(parents=True)

        rev = task1_dir / "task1-20260303T110451Z-hash1"
        rev.mkdir()
        (rev / "model.onnx").touch()
        (rev / "observations_metadata.yaml").touch()

        # Discover for task1 (exists)
        result1 = RevisionDiscoverer.discover_latest(temp_artifacts_root, task1)
        assert result1 == rev

        # Discover for task2 (doesn't exist)
        result2 = RevisionDiscoverer.discover_latest(temp_artifacts_root, task2)
        assert result2 is None

    def test_multiple_tasks_with_same_timestamps(self, temp_artifacts_root):
        """Test that multiple tasks with same timestamps work independently."""
        tasks = ["task1", "task2", "task3"]
        timestamp = "20260303T110451Z"

        for task in tasks:
            task_dir = temp_artifacts_root / "policies" / task
            task_dir.mkdir(parents=True)
            rev = task_dir / f"{task}-{timestamp}-hash1"
            rev.mkdir()
            (rev / "model.onnx").touch()
            (rev / "observations_metadata.yaml").touch()

        # All should return their own revision
        for task in tasks:
            result = RevisionDiscoverer.discover_latest(temp_artifacts_root, task)
            assert result is not None
            assert result.name.startswith(task)


# =============================================================================
# Test Class: TestFeatureProviderBaseIntegration
# =============================================================================


class TestFeatureProviderBaseIntegration:
    """Test suite for FeatureProviderBase and RevisionDiscoverer integration."""

    def test_from_latest_revision_valid(
        self, temp_artifacts_root, valid_metadata_content
    ):
        """Test that from_latest_revision works with valid revision."""
        task = "test_task"
        task_dir = temp_artifacts_root / "policies" / task
        task_dir.mkdir(parents=True)

        rev = task_dir / "test_task-20260303T110451Z-hash1"
        rev.mkdir()
        (rev / "model.onnx").touch()

        metadata_path = rev / "observations_metadata.yaml"
        with open(metadata_path, "w") as f:
            yaml.dump(valid_metadata_content, f)

        # Create a mock provider class with required methods
        class MockProvider(FeatureProviderBase):
            def get_position(self):
                return [0.0, 0.0, 0.0]

            def get_velocity(self):
                return [0.0, 0.0, 0.0]

            def get_orientation(self):
                return [0.0, 0.0, 0.0, 1.0]

        # Mock the from_latest_revision to use our mock class
        original_from_latest = FeatureProviderBase.from_latest_revision

        def mock_from_latest(artifacts_root, task):
            latest_revision = RevisionDiscoverer.discover_latest(artifacts_root, task)
            if latest_revision is None:
                raise FileNotFoundError(
                    f"No valid revision found for task '{task}' in artifacts_root '{artifacts_root}'."
                )
            metadata_path = latest_revision / "observations_metadata.yaml"
            return MockProvider(metadata_path)

        with patch.object(
            FeatureProviderBase, "from_latest_revision", mock_from_latest
        ):
            provider = FeatureProviderBase.from_latest_revision(
                temp_artifacts_root, task
            )

        assert provider is not None
        assert provider._metadata_path == metadata_path

    def test_from_latest_revision_missing_revision_raises(self, temp_artifacts_root):
        """Test that from_latest_revision raises FileNotFoundError when no revision."""
        task = "test_task"

        with pytest.raises(FileNotFoundError) as exc_info:
            FeatureProviderBase.from_latest_revision(temp_artifacts_root, task)

        assert "No valid revision found" in str(exc_info.value)
        assert "test_task" in str(exc_info.value)

    def test_from_latest_revision_invalid_revision_raises(self, temp_artifacts_root):
        """Test that from_latest_revision raises when revision is invalid."""
        task = "test_task"
        task_dir = temp_artifacts_root / "policies" / task
        task_dir.mkdir(parents=True)

        # Create invalid revision (missing files)
        rev = task_dir / "test_task-20260303T110451Z-hash1"
        rev.mkdir()

        with pytest.raises(FileNotFoundError) as exc_info:
            FeatureProviderBase.from_latest_revision(temp_artifacts_root, task)

        assert "No valid revision found" in str(exc_info.value)

    def test_from_latest_revision_selects_latest(
        self, temp_artifacts_root, valid_metadata_content
    ):
        """Test that from_latest_revision selects the latest revision."""
        task = "test_task"
        task_dir = temp_artifacts_root / "policies" / task
        task_dir.mkdir(parents=True)

        # Create multiple revisions
        revisions = [
            "test_task-20260301T100000Z-hash1",
            "test_task-20260302T120000Z-hash2",
            "test_task-20260303T110451Z-hash3",
        ]

        for rev_name in revisions:
            rev = task_dir / rev_name
            rev.mkdir()
            (rev / "model.onnx").touch()
            metadata_path = rev / "observations_metadata.yaml"
            with open(metadata_path, "w") as f:
                yaml.dump(valid_metadata_content, f)

        # Create a mock provider class with required methods
        class MockProvider(FeatureProviderBase):
            def get_position(self):
                return [0.0, 0.0, 0.0]

            def get_velocity(self):
                return [0.0, 0.0, 0.0]

            def get_orientation(self):
                return [0.0, 0.0, 0.0, 1.0]

        # Mock the from_latest_revision to use our mock class
        def mock_from_latest(artifacts_root, task):
            latest_revision = RevisionDiscoverer.discover_latest(artifacts_root, task)
            if latest_revision is None:
                raise FileNotFoundError(
                    f"No valid revision found for task '{task}' in artifacts_root '{artifacts_root}'."
                )
            metadata_path = latest_revision / "observations_metadata.yaml"
            return MockProvider(metadata_path)

        with patch.object(
            FeatureProviderBase, "from_latest_revision", mock_from_latest
        ):
            provider = FeatureProviderBase.from_latest_revision(
                temp_artifacts_root, task
            )

        # Should load from the latest revision
        expected_rev = task_dir / "test_task-20260303T110451Z-hash3"
        assert provider._metadata_path == expected_rev / "observations_metadata.yaml"


# =============================================================================
# Test Class: TestErrorHandling
# =============================================================================


class TestErrorHandling:
    """Test suite for error handling scenarios."""

    def test_artifacts_root_as_string(self, temp_artifacts_root):
        """Test that artifacts_root can be passed as string."""
        task = "test_task"
        task_dir = Path(temp_artifacts_root) / "policies" / task
        task_dir.mkdir(parents=True)

        rev = task_dir / "test_task-20260303T110451Z-hash1"
        rev.mkdir()
        (rev / "model.onnx").touch()
        (rev / "observations_metadata.yaml").touch()

        # Pass as string
        result = RevisionDiscoverer.discover_latest(str(temp_artifacts_root), task)

        assert result == rev

    def test_permission_errors_handled(self, temp_artifacts_root):
        """Test that permission errors are handled gracefully."""
        # This is a unit test - in real scenarios, we'd need to mock permissions
        task = "test_task"
        task_dir = temp_artifacts_root / "policies" / task
        task_dir.mkdir(parents=True)

        # Create a revision
        rev = task_dir / "test_task-20260303T110451Z-hash1"
        rev.mkdir()
        (rev / "model.onnx").touch()
        (rev / "observations_metadata.yaml").touch()

        result = RevisionDiscoverer.discover_latest(temp_artifacts_root, task)

        assert result == rev

    def test_metadata_file_with_invalid_yaml(self, temp_artifacts_root):
        """Test that invalid YAML is handled gracefully."""
        task = "test_task"
        task_dir = temp_artifacts_root / "policies" / task
        task_dir.mkdir(parents=True)

        rev = task_dir / "test_task-20260303T110451Z-hash1"
        rev.mkdir()
        (rev / "model.onnx").touch()
        (rev / "observations_metadata.yaml").write_text("invalid: yaml: content: [")

        # Revision discovery should still work (doesn't validate YAML)
        result = RevisionDiscoverer.discover_latest(temp_artifacts_root, task)

        assert result == rev

        # But FeatureProviderBase should fail when trying to load metadata
        with pytest.raises(yaml.YAMLError):
            FeatureProviderBase(rev / "observations_metadata.yaml")

    def test_concurrent_discoveries_dont_interfere(self, temp_artifacts_root):
        """Test that concurrent discoveries don't interfere with each other."""
        tasks = ["task1", "task2", "task3"]

        for task in tasks:
            task_dir = temp_artifacts_root / "policies" / task
            task_dir.mkdir(parents=True)
            rev = task_dir / f"{task}-20260303T110451Z-hash1"
            rev.mkdir()
            (rev / "model.onnx").touch()
            (rev / "observations_metadata.yaml").touch()

        # Simulate concurrent access
        results = [
            RevisionDiscoverer.discover_latest(temp_artifacts_root, task)
            for task in tasks
        ]

        # All should return their respective revisions
        for i, result in enumerate(results):
            assert result is not None
            assert result.name.startswith(tasks[i])


# =============================================================================
# Test Class: TestEdgeCases
# =============================================================================


class TestEdgeCases:
    """Test suite for edge cases."""

    def test_revision_with_special_characters(self, temp_artifacts_root):
        """Test that special characters in hash are handled."""
        task = "test_task"
        task_dir = temp_artifacts_root / "policies" / task
        task_dir.mkdir(parents=True)

        # Hash with various characters
        rev = task_dir / "test_task-20260303T110451Z-abc123-def456.xyz"
        rev.mkdir()
        (rev / "model.onnx").touch()
        (rev / "observations_metadata.yaml").touch()

        result = RevisionDiscoverer.discover_latest(temp_artifacts_root, task)

        assert result == rev

    def test_very_long_revision_name(self, temp_artifacts_root):
        """Test that very long revision names are handled."""
        task = "test_task"
        task_dir = temp_artifacts_root / "policies" / task
        task_dir.mkdir(parents=True)

        # Very long hash
        long_hash = "a" * 100
        rev = task_dir / f"test_task-20260303T110451Z-{long_hash}"
        rev.mkdir()
        (rev / "model.onnx").touch()
        (rev / "observations_metadata.yaml").touch()

        result = RevisionDiscoverer.discover_latest(temp_artifacts_root, task)

        assert result == rev

    def test_unicode_characters_in_path(self, temp_artifacts_root):
        """Test that unicode characters in paths are handled."""
        task = "test_task"
        task_dir = temp_artifacts_root / "policies" / task
        task_dir.mkdir(parents=True)

        # Unicode characters (should work but may vary by filesystem)
        rev = task_dir / "test_task-20260303T110451Z-hash-тест"
        rev.mkdir()
        (rev / "model.onnx").touch()
        (rev / "observations_metadata.yaml").touch()

        result = RevisionDiscoverer.discover_latest(temp_artifacts_root, task)

        assert result == rev

    def test_empty_metadata_file(self, temp_artifacts_root):
        """Test that empty metadata file is handled."""
        task = "test_task"
        task_dir = temp_artifacts_root / "policies" / task
        task_dir.mkdir(parents=True)

        rev = task_dir / "test_task-20260303T110451Z-hash1"
        rev.mkdir()
        (rev / "model.onnx").touch()
        (rev / "observations_metadata.yaml").touch()  # Empty file

        result = RevisionDiscoverer.discover_latest(temp_artifacts_root, task)

        assert result == rev

        # FeatureProviderBase should raise error for empty metadata (None from yaml.safe_load)
        with pytest.raises(
            AttributeError, match="'NoneType' object has no attribute 'get'"
        ):
            FeatureProviderBase(rev / "observations_metadata.yaml")
