"""Train the MLP on augmented MNIST: python -m training.train -> training/out/model.pt."""

import math
import time

import torch
import torch.nn.functional as F
from torch import nn
from torchvision import datasets

from training import config


def build_model() -> nn.Sequential:
    layers: list[nn.Module] = []
    sizes = config.LAYER_SIZES
    for i in range(len(sizes) - 1):
        layers.append(nn.Linear(sizes[i], sizes[i + 1]))
        if i < len(sizes) - 2:
            layers.append(nn.ReLU())
    return nn.Sequential(*layers)


def load_mnist(train: bool) -> tuple[torch.Tensor, torch.Tensor]:
    """Return images as (N, 1, 28, 28) floats in [0, 1] with ink = 1, and labels."""
    dataset = datasets.MNIST(str(config.DATA_DIR), train=train, download=True)
    images = dataset.data.float().unsqueeze(1) / 255.0
    return images, dataset.targets


def split_train_validation() -> tuple[torch.Tensor, torch.Tensor, torch.Tensor, torch.Tensor]:
    images, labels = load_mnist(train=True)
    generator = torch.Generator().manual_seed(config.SEED)
    order = torch.randperm(len(images), generator=generator)
    validation = order[: config.VALIDATION_SIZE]
    train = order[config.VALIDATION_SIZE :]
    return images[train], labels[train], images[validation], labels[validation]


def _affine_jitter(images: torch.Tensor) -> torch.Tensor:
    count = len(images)
    angle = torch.empty(count).uniform_(-config.AUG_ROTATION_DEGREES, config.AUG_ROTATION_DEGREES)
    angle = angle * math.pi / 180.0
    scale = torch.empty(count).uniform_(config.AUG_SCALE_MIN, config.AUG_SCALE_MAX)
    shear = torch.empty(count).uniform_(-config.AUG_SHEAR, config.AUG_SHEAR)
    half_grid = config.GRID / 2.0
    max_shift = config.AUG_SHIFT_PIXELS / half_grid
    shift_x = torch.empty(count).uniform_(-max_shift, max_shift)
    shift_y = torch.empty(count).uniform_(-max_shift, max_shift)

    cos = torch.cos(angle) / scale
    sin = torch.sin(angle) / scale
    theta = torch.stack(
        [
            torch.stack([cos, -sin + shear * cos, shift_x], dim=1),
            torch.stack([sin, cos + shear * sin, shift_y], dim=1),
        ],
        dim=1,
    )
    grid = F.affine_grid(theta, list(images.shape), align_corners=False)
    return F.grid_sample(images, grid, mode="bilinear", padding_mode="zeros", align_corners=False)


def _thickness_jitter(images: torch.Tensor) -> torch.Tensor:
    """Blend each selected image toward its dilation or erosion by a random amount."""
    count = len(images)
    dilated = F.max_pool2d(images, kernel_size=3, stride=1, padding=1)
    eroded = -F.max_pool2d(-images, kernel_size=3, stride=1, padding=1)
    roll = torch.rand(count, 1, 1, 1)
    blend = torch.rand(count, 1, 1, 1)
    dilate_mask = (roll < config.AUG_DILATE_PROBABILITY).float() * blend
    erode_cutoff = config.AUG_DILATE_PROBABILITY + config.AUG_ERODE_PROBABILITY
    erode_mask = ((roll >= config.AUG_DILATE_PROBABILITY) & (roll < erode_cutoff)).float() * blend
    images = images + (dilated - images) * dilate_mask
    return images + (eroded - images) * erode_mask


def _mild_blur(images: torch.Tensor) -> torch.Tensor:
    kernel = torch.tensor([[1.0, 2.0, 1.0], [2.0, 4.0, 2.0], [1.0, 2.0, 1.0]]) / 16.0
    blurred = F.conv2d(images, kernel.view(1, 1, 3, 3), padding=1)
    mask = (torch.rand(len(images), 1, 1, 1) < config.AUG_BLUR_PROBABILITY).float()
    return images + (blurred - images) * mask


def augment(images: torch.Tensor) -> torch.Tensor:
    return _mild_blur(_thickness_jitter(_affine_jitter(images))).clamp(0.0, 1.0)


@torch.no_grad()
def accuracy(model: nn.Module, images: torch.Tensor, labels: torch.Tensor) -> float:
    predictions = model(images.flatten(1)).argmax(dim=1)
    return 100.0 * (predictions == labels).float().mean().item()


def main() -> None:
    torch.manual_seed(config.SEED)

    train_images, train_labels, val_images, val_labels = split_train_validation()
    test_images, test_labels = load_mnist(train=False)

    model = build_model()
    optimizer = torch.optim.AdamW(model.parameters(), lr=config.LEARNING_RATE, weight_decay=config.WEIGHT_DECAY)
    steps_per_epoch = math.ceil(len(train_images) / config.BATCH_SIZE)
    scheduler = torch.optim.lr_scheduler.CosineAnnealingLR(optimizer, T_max=config.EPOCHS * steps_per_epoch)

    best_val = -1.0
    best_state: dict[str, torch.Tensor] = {}
    started = time.time()
    for epoch in range(1, config.EPOCHS + 1):
        model.train()
        order = torch.randperm(len(train_images))
        for start in range(0, len(train_images), config.BATCH_SIZE):
            batch = order[start : start + config.BATCH_SIZE]
            inputs = augment(train_images[batch]).flatten(1)
            loss = F.cross_entropy(model(inputs), train_labels[batch])
            optimizer.zero_grad()
            loss.backward()
            optimizer.step()
            scheduler.step()

        model.eval()
        val_acc = accuracy(model, val_images, val_labels)
        if val_acc >= best_val:
            best_val = val_acc
            best_state = {name: value.clone() for name, value in model.state_dict().items()}
        print(f"epoch {epoch:3d}  val {val_acc:6.2f}%  best {best_val:6.2f}%  {time.time() - started:5.0f}s", flush=True)

    model.load_state_dict(best_state)
    config.OUT_DIR.mkdir(parents=True, exist_ok=True)
    torch.save({"state_dict": best_state, "layer_sizes": config.LAYER_SIZES}, config.CHECKPOINT_PATH)
    print(f"float test accuracy: {accuracy(model, test_images, test_labels):.2f}%")
    print(f"saved {config.CHECKPOINT_PATH}")


if __name__ == "__main__":
    main()
