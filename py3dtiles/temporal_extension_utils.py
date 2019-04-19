def temporal_extract_bounding_dates(objects_with_dates):
    """
    :param objects_with_dates: an iterable withholding items that have the
                               get_creation_date() and get_deletion_date()
                               methods
    :return: the earliest creation date and the latest deletion dates found
             among the given (set of) items
    """
    # Initialize with whatever value
    creation_date = objects_with_dates[0].get_start_date()
    deletion_date = objects_with_dates[0].get_end_date()
    for building in objects_with_dates:
        if building.get_start_date() < creation_date:
            creation_date = building.get_start_date()
        if building.get_end_date() > deletion_date:
            deletion_date = building.get_end_date()
    return {'start_date': creation_date, 'end_date': deletion_date}
