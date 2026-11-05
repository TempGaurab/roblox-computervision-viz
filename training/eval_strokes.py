"""Accuracy on recorded drawings in tests/fixtures/strokes: python -m training.eval_strokes."""

import base64

import numpy as np
import torch

from training import config
from training.export import load_stroke_fixtures, logits_of, quantize_layers
from training.preprocess import decode_strokes, preprocess


def main() -> None:
    fixtures = load_stroke_fixtures()
    if not fixtures:
        print(f"no fixtures in {config.STROKE_FIXTURE_DIR.relative_to(config.REPO_ROOT)}")
        return

    checkpoint = torch.load(config.CHECKPOINT_PATH, weights_only=True)
    layers = quantize_layers(checkpoint["state_dict"])

    correct = 0
    total_ink = 0.0
    for fixture in fixtures:
        image = preprocess(*decode_strokes(base64.b64decode(fixture.encoded)))
        if image is None:
            print(f"{fixture.name}: too small to read")
            continue
        total_ink += float(image.sum())
        predicted = int(logits_of(layers, image[np.newaxis])[0].argmax())
        correct += predicted == fixture.digit
        if predicted != fixture.digit:
            print(f"{fixture.name}: predicted {predicted}")

    print(f"accuracy {100.0 * correct / len(fixtures):.2f}% on {len(fixtures)} fixtures")
    print(f"mean total ink {total_ink / len(fixtures):.1f} (calibration target: about 100)")


if __name__ == "__main__":
    main()
