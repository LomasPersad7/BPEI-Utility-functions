from PIL import ImageChops, ImageStat

def image_difference(img1, img2):
    """Return average pixel difference between two images."""
    diff = ImageChops.difference(img1, img2)
    stat = ImageStat.Stat(diff)
    return sum(stat.mean)


def is_same(img1, img2, threshold=2.0):
    """Check if two images are effectively the same."""
    return image_difference(img1, img2) < threshold