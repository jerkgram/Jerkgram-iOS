load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "ChatSearchNavigationContentNode",
    module_name = "ChatSearchNavigationContentNode",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//submodules/PresentationDataUtils:PresentationDataUtils",
        "//submodules/AlertUI:AlertUI",
        "//submodules/ItemListUI:ItemListUI",
        "//submodules/JerkgramCore:JerkgramCore",
        "//submodules/AsyncDisplayKit",
        "//submodules/Display",
        "//submodules/TelegramPresentationData",
        "//submodules/ChatPresentationInterfaceState",
        "//submodules/TelegramCore",
        "//submodules/SearchBarNode",
        "//submodules/LocalizedPeerData",
        "//submodules/AccountContext",
        "//submodules/SSignalKit/SwiftSignalKit",
        "//submodules/TelegramUI/Components/GlassBackgroundComponent",
        "//submodules/ComponentFlow",
        "//submodules/Components/ComponentDisplayAdapters",
        "//submodules/ActivityIndicator",
    ],
    visibility = [
        "//visibility:public",
    ],
)
