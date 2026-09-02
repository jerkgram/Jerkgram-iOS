import PBXProj

extension ElementCreator {
    struct CreateGroup {
        private let createGroupElement: CreateGroupElement
        private let createGroupChildElements:
            CreateGroupChildElements

        private let callable: Callable

        /// - Parameters:
        ///   - callable: The function that will be called in
        ///     `callAsFunction()`.
        init(
            createGroupChildElements:
                CreateGroupChildElements,
            createGroupElement: CreateGroupElement,
            callable: @escaping Callable
        ) {
            self.createGroupChildElements = createGroupChildElements
            self.createGroupElement = createGroupElement

            self.callable = callable
        }

        func callAsFunction(
            name: String,
            nodeChildren: [PathTreeNode],
            parentBazelPath: BazelPath,
            bazelPathType: BazelPathType,
            // Passed in to prevent infinite size
            // (i.e. CreateGroup -> CreateGroupChild -> CreateGroup)
            createGroupChild: CreateGroupChild
        ) -> GroupChild.ElementAndChildren {
            return callable(
                /*name:*/ name,
                /*nodeChildren:*/ nodeChildren,
                /*parentBazelPath:*/ parentBazelPath,
                /*bazelPathType:*/ bazelPathType,
                /*createGroupChild:*/ createGroupChild,
                /*createGroupChildElements:*/ createGroupChildElements,
                /*createGroupElement:*/ createGroupElement
            )
        }
    }
}

// MARK: - CreateGroup.Callable

extension ElementCreator.CreateGroup {
    typealias Callable = (
        _ name: String,
        _ nodeChildren: [PathTreeNode],
        _ parentBazelPath: BazelPath,
        _ bazelPathType: BazelPathType,
        _ createGroupChild: ElementCreator.CreateGroupChild,
        _ createGroupChildElements: ElementCreator.CreateGroupChildElements,
        _ createGroupElement: ElementCreator.CreateGroupElement
    ) -> GroupChild.ElementAndChildren

    static func defaultCallable(
        name: String,
        nodeChildren: [PathTreeNode],
        parentBazelPath: BazelPath,
        bazelPathType: BazelPathType,
        createGroupChild: ElementCreator.CreateGroupChild,
        createGroupChildElements: ElementCreator.CreateGroupChildElements,
        createGroupElement: ElementCreator.CreateGroupElement
    ) -> GroupChild.ElementAndChildren {
        let bazelPath = BazelPath(parent: parentBazelPath, path: name)

        let groupChildren = nodeChildren.map { node in
            return createGroupChild(
                for: node,
                parentBazelPath: bazelPath,
                parentBazelPathType: bazelPathType
            )
        }

        let children = createGroupChildElements(
            parentBazelPath: bazelPath,
            groupChildren: groupChildren
        )

        let (
            group,
            resolvedRepository
        ) = createGroupElement(
            name: name,
            bazelPath: bazelPath,
            bazelPathType: bazelPathType,
            childIdentifiers: children.elements.map(\.object.identifier)
        )

        return GroupChild.ElementAndChildren(
            bazelPath: bazelPath,
            element: group,
            includeParentInBazelPathAndIdentifiers: false,
            resolvedRepository: resolvedRepository,
            children: children
        )
    }
}
