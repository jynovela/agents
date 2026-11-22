"""Price statistics for items returned by the inventory service."""


def average_price(items):
    """Return the average price of the items."""
    prices = [float(item["price"]) for item in items]
    return sum(prices) / len(prices) if prices else 0.0
