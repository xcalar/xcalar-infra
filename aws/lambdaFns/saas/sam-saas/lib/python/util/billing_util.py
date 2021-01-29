from constants.price import price_table, raw_price_table
def get_price(instance_type, instance_count, divisor=60):
    if instance_type not in price_table:
        # For testing purpose
        if instance_type not in raw_price_table:
            return 1.0 / divisor
        return 3 * raw_price_table[instance_type] * instance_count / divisor
    return  price_table[instance_type] * instance_count / divisor