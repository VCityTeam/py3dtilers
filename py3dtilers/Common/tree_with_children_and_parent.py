class TreeWithChildrenAndParent:
    """
    A simple hierarchy/Direct Acyclic Graph, as in
    https://en.wikipedia.org/wiki/Tree_%28data_structure%29) with both
    children and parent relationships explicitly represented (for the
    sake of retrieval efficiency) as dictionaries using some user
    defined identifier as keys. TreeWithChildrenAndParent is not
    responsible of the identifiers and simply uses them as provided
    weak references.
    """

    def __init__(self):
        """Children of a given id (given as dict key)"""
        self.hierarchy = {}
        """Parents of a given id (given as dict key)"""
        self.reverseHierarchy = {}

    def addNodeToParent(self, object_id, parent_id):
        if parent_id is not None:
            if parent_id not in self.hierarchy:
                self.hierarchy[parent_id] = []
            if object_id not in self.hierarchy[parent_id]:
                self.hierarchy[parent_id].append(object_id)
                self.reverseHierarchy[object_id] = parent_id

    def getParents(self, object_id):
        if object_id in self.reverseHierarchy:
            return [self.reverseHierarchy[object_id]]
        return []
