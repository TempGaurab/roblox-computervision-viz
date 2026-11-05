"""Single source for the architecture, preprocessing constants, and training settings."""

from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
DATA_DIR = REPO_ROOT / "training" / "data"
OUT_DIR = REPO_ROOT / "training" / "out"
CHECKPOINT_PATH = OUT_DIR / "model.pt"
MODEL_DATA_PATH = REPO_ROOT / "src" / "shared" / "NeuralCore" / "ModelData.luau"
DEV_FIXTURES_PATH = REPO_ROOT / "src" / "client" / "Dev" / "Fixtures.luau"
GOLDEN_DIR = REPO_ROOT / "tests" / "golden"
STROKE_FIXTURE_DIR = REPO_ROOT / "tests" / "fixtures" / "strokes"

# Architecture. Luau reads every shape from ModelData, so this is the only place they are set.
LAYER_SIZES: tuple[int, ...] = (784, 64, 32, 10)

# Preprocessing, shared with NeuralCore/Preprocess.luau through ModelData.
GRID = 28
BOX = 20
# Calibrate against recorded fixtures: they should average about 100 total ink.
BRUSH_INNER = 1.0
BRUSH_OUTER = 2.0
MIN_EXTENT = 0.04

# Stroke limits, mirrored by NeuralCore/Strokes.luau.
MAX_STROKES = 32
MAX_POINTS = 1024

# Training.
SEED = 1337
VALIDATION_SIZE = 5000
EPOCHS = 40
BATCH_SIZE = 128
LEARNING_RATE = 2e-3
WEIGHT_DECAY = 1e-4

# Augmentation, closing the gap between scanned pen strokes and mouse or finger drawing.
AUG_ROTATION_DEGREES = 12.0
AUG_SCALE_MIN = 0.85
AUG_SCALE_MAX = 1.15
AUG_SHEAR = 0.1
AUG_SHIFT_PIXELS = 2.0
AUG_DILATE_PROBABILITY = 0.25
AUG_ERODE_PROBABILITY = 0.15
AUG_BLUR_PROBABILITY = 0.3

# Quantization and export.
INT8_MAX = 127
ACT_SCALE_PERCENTILE = 99.0
MAX_GENERATED_CHARS = 190_000
GOLDEN_SEED = 20261105
GOLDEN_MNIST_CASES = 32
GOLDEN_POLYLINE_CASES = 16
DEV_FIXTURES_PER_DIGIT = 3

# Accuracy targets, in percentage points.
TARGET_FLOAT_ACC = 97.0
TARGET_INT8_MAX_DROP = 0.3
TARGET_FIXTURE_ACC = 90.0
TARGET_FIXTURE_MIN_COUNT = 50
