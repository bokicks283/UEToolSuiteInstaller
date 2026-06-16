"use strict";
(globalThis["webpackChunkue_project_docs"] = globalThis["webpackChunkue_project_docs"] || []).push([[3494],{

/***/ 8563
(__unused_webpack_module, __webpack_exports__, __webpack_require__) {

// ESM COMPAT FLAG
__webpack_require__.r(__webpack_exports__);

// EXPORTS
__webpack_require__.d(__webpack_exports__, {
  assets: () => (/* binding */ assets),
  contentTitle: () => (/* binding */ contentTitle),
  "default": () => (/* binding */ MDXContent),
  frontMatter: () => (/* binding */ frontMatter),
  metadata: () => (/* reexport */ site_docs_workflow_standards_coding_standards_unreal_cpp_standard_md_d5d_namespaceObject),
  toc: () => (/* binding */ toc)
});

;// ./.docusaurus/docusaurus-plugin-content-docs/default/site-docs-workflow-standards-coding-standards-unreal-cpp-standard-md-d5d.json
const site_docs_workflow_standards_coding_standards_unreal_cpp_standard_md_d5d_namespaceObject = /*#__PURE__*/JSON.parse('{"id":"WorkflowStandards/CodingStandards/UnrealCppStandard","title":"Unreal C++ Coding Standard (UE 5.7)","description":"At Epic Games, we have a few simple coding standards and conventions. This document reflects the state of Epic Games\' current coding standards. Following the coding standards is mandatory.","source":"@site/../Docs/WorkflowStandards/CodingStandards/UnrealCppStandard.md","sourceDirName":"WorkflowStandards/CodingStandards","slug":"/coding-standards/unreal-cpp-standard","permalink":"/docs/coding-standards/unreal-cpp-standard","draft":false,"unlisted":false,"tags":[],"version":"current","sidebarPosition":1,"frontMatter":{"title":"Unreal C++ Coding Standard (UE 5.7)","slug":"/coding-standards/unreal-cpp-standard","sidebar_position":1},"sidebar":"workflow-standards-sidebar","previous":{"title":"Coding Standards","permalink":"/docs/coding-standards"},"next":{"title":"Testing","permalink":"/docs/testing"}}');
// EXTERNAL MODULE: ./node_modules/react/jsx-runtime.js
var jsx_runtime = __webpack_require__(4848);
// EXTERNAL MODULE: ./node_modules/@mdx-js/react/lib/index.js
var lib = __webpack_require__(8453);
;// ../Docs/WorkflowStandards/CodingStandards/UnrealCppStandard.md


const frontMatter = {
	title: 'Unreal C++ Coding Standard (UE 5.7)',
	slug: '/coding-standards/unreal-cpp-standard',
	sidebar_position: 1
};
const contentTitle = undefined;

const assets = {

};



const toc = [{
  "value": "Class Organization",
  "id": "class-organization",
  "level": 2
}, {
  "value": "Copyright Notice",
  "id": "copyright-notice",
  "level": 2
}, {
  "value": "Naming Conventions",
  "id": "naming-conventions",
  "level": 2
}, {
  "value": "Inclusive Word Choice",
  "id": "inclusive-word-choice",
  "level": 2
}, {
  "value": "Racial, ethnic, and religious inclusiveness",
  "id": "racial-ethnic-and-religious-inclusiveness",
  "level": 3
}, {
  "value": "Gender inclusiveness",
  "id": "gender-inclusiveness",
  "level": 3
}, {
  "value": "Slang",
  "id": "slang",
  "level": 3
}, {
  "value": "Overloaded Words",
  "id": "overloaded-words",
  "level": 3
}, {
  "value": "Word List",
  "id": "word-list",
  "level": 3
}, {
  "value": "Portable C++ code",
  "id": "portable-c-code",
  "level": 2
}, {
  "value": "Use of standard libraries",
  "id": "use-of-standard-libraries",
  "level": 2
}, {
  "value": "Comments",
  "id": "comments",
  "level": 2
}, {
  "value": "Guidelines",
  "id": "guidelines",
  "level": 3
}, {
  "value": "Const Correctness",
  "id": "const-correctness",
  "level": 3
}, {
  "value": "Example Formatting",
  "id": "example-formatting",
  "level": 3
}, {
  "value": "Modern C++ Language Syntax",
  "id": "modern-c-language-syntax",
  "level": 2
}, {
  "value": "Static Assert",
  "id": "static-assert",
  "level": 3
}, {
  "value": "Override and Final",
  "id": "override-and-final",
  "level": 3
}, {
  "value": "Nullptr",
  "id": "nullptr",
  "level": 3
}, {
  "value": "Auto",
  "id": "auto",
  "level": 3
}, {
  "value": "Range-Based For",
  "id": "range-based-for",
  "level": 3
}, {
  "value": "Lambdas and Anonymous Functions",
  "id": "lambdas-and-anonymous-functions",
  "level": 3
}, {
  "value": "Captures and Return Types",
  "id": "captures-and-return-types",
  "level": 4
}, {
  "value": "Strongly-Typed Enums",
  "id": "strongly-typed-enums",
  "level": 3
}, {
  "value": "Move Semantics",
  "id": "move-semantics",
  "level": 3
}, {
  "value": "Default Member Initializers",
  "id": "default-member-initializers",
  "level": 3
}, {
  "value": "Third Party Code",
  "id": "third-party-code",
  "level": 2
}, {
  "value": "Code Formatting",
  "id": "code-formatting",
  "level": 2
}, {
  "value": "Braces",
  "id": "braces",
  "level": 3
}, {
  "value": "If - Else",
  "id": "if---else",
  "level": 3
}, {
  "value": "Tabs and Indenting",
  "id": "tabs-and-indenting",
  "level": 3
}, {
  "value": "Switch Statements",
  "id": "switch-statements",
  "level": 3
}, {
  "value": "Namespaces",
  "id": "namespaces",
  "level": 2
}, {
  "value": "Physical Dependencies",
  "id": "physical-dependencies",
  "level": 2
}, {
  "value": "Encapsulation",
  "id": "encapsulation",
  "level": 2
}, {
  "value": "General Style Issues",
  "id": "general-style-issues",
  "level": 2
}, {
  "value": "API Design Guidelines",
  "id": "api-design-guidelines",
  "level": 2
}, {
  "value": "Platform-Specific Code",
  "id": "platform-specific-code",
  "level": 2
}];
function _createMdxContent(props) {
  const _components = {
    a: "a",
    code: "code",
    em: "em",
    h2: "h2",
    h3: "h3",
    h4: "h4",
    li: "li",
    p: "p",
    pre: "pre",
    strong: "strong",
    table: "table",
    tbody: "tbody",
    td: "td",
    th: "th",
    thead: "thead",
    tr: "tr",
    ul: "ul",
    ...(0,lib/* useMDXComponents */.R)(),
    ...props.components
  };
  return (0,jsx_runtime.jsxs)(jsx_runtime.Fragment, {
    children: [(0,jsx_runtime.jsx)(_components.p, {
      children: "At Epic Games, we have a few simple coding standards and conventions. This document reflects the state of Epic Games' current coding standards. Following the coding standards is mandatory."
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "Code conventions are important to programmers for several reasons:"
    }), "\n", (0,jsx_runtime.jsxs)(_components.ul, {
      children: ["\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsx)(_components.p, {
          children: "80% of the lifetime cost of a piece of software goes to maintenance."
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsx)(_components.p, {
          children: "Hardly any software is maintained for its whole life by the original author."
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsx)(_components.p, {
          children: "Code conventions improve the readability of software, allowing engineers to understand new code quickly and thoroughly."
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsx)(_components.p, {
          children: "If we decide to expose source code to mod community developers, we want it to be easily understood."
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsx)(_components.p, {
          children: "Many of these conventions are required for cross-compiler compatibility."
        }), "\n"]
      }), "\n"]
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "The coding standards below are C++-centric; however, the standard is expected to be followed no matter which language is used. A section may provide equivalent rules or exceptions for specific languages where it's applicable."
    }), "\n", (0,jsx_runtime.jsx)(_components.h2, {
      id: "class-organization",
      children: "Class Organization"
    }), "\n", (0,jsx_runtime.jsxs)(_components.p, {
      children: [(0,jsx_runtime.jsx)(_components.strong, {
        children: "Classes"
      }), " should be organized with the reader in mind rather than the writer. Since most readers will use the public interface of the class, the public implementation should be declared first, followed by the class's private implementation."]
    }), "\n", (0,jsx_runtime.jsx)(_components.pre, {
      children: (0,jsx_runtime.jsx)(_components.code, {
        className: "language-cpp",
        children: "UCLASS()\n\nclass EXAMPLEPROJECT_API AExampleActor : public AActor\n{\n    GENERATED_BODY()\n\npublic:\n    // Sets default values for this actor's properties\n    AExampleActor();\n\nprotected:\n\n    // Called when the game starts or when spawned\n    virtual void BeginPlay() override;\n};\n"
      })
    }), "\n", (0,jsx_runtime.jsx)(_components.h2, {
      id: "copyright-notice",
      children: "Copyright Notice"
    }), "\n", (0,jsx_runtime.jsxs)(_components.p, {
      children: ["Any source file (", (0,jsx_runtime.jsx)(_components.code, {
        children: ".h"
      }), ", ", (0,jsx_runtime.jsx)(_components.code, {
        children: ".cpp"
      }), ", ", (0,jsx_runtime.jsx)(_components.code, {
        children: ".xaml"
      }), ") provided by Epic Games for public distribution must contain a copyright notice as the first line in the file. The format of the notice must exactly match that shown below:"]
    }), "\n", (0,jsx_runtime.jsx)(_components.pre, {
      children: (0,jsx_runtime.jsx)(_components.code, {
        className: "language-cpp",
        children: "// Copyright Epic Games, Inc. All Rights Reserved.\n"
      })
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "If this line is missing or not formatted properly, CIS will generate an error and fail."
    }), "\n", (0,jsx_runtime.jsx)(_components.h2, {
      id: "naming-conventions",
      children: "Naming Conventions"
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "When using Naming Conventions, all code and comments should use U.S. English spelling and grammar."
    }), "\n", (0,jsx_runtime.jsxs)(_components.ul, {
      children: ["\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["The first letter of each word in a name (such as type name or variable name) is capitalized. There is usually no underscore between words. For example, ", (0,jsx_runtime.jsx)(_components.code, {
          children: "Health"
        }), " and ", (0,jsx_runtime.jsx)(_components.code, {
          children: "UPrimitiveComponent"
        }), " are correct, but ", (0,jsx_runtime.jsx)(_components.code, {
          children: "lastMouseCoordinates"
        }), " or ", (0,jsx_runtime.jsx)(_components.code, {
          children: "delta_coordinates"
        }), " are not."]
      }), "\n"]
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "This is PascalCase formatting for users who may be familiar with other object oriented programming languages"
    }), "\n", (0,jsx_runtime.jsxs)(_components.ul, {
      children: ["\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsxs)(_components.p, {
          children: ["Type names are prefixed with an additional upper-case letter to distinguish them from variable names. For example, ", (0,jsx_runtime.jsx)(_components.code, {
            children: "FSkin"
          }), " is a type name, and ", (0,jsx_runtime.jsx)(_components.code, {
            children: "Skin"
          }), " is an instance of type ", (0,jsx_runtime.jsx)(_components.code, {
            children: "FSkin"
          }), "."]
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsx)(_components.p, {
          children: "Template classes are prefixed by T."
        }), "\n"]
      }), "\n"]
    }), "\n", (0,jsx_runtime.jsx)(_components.pre, {
      children: (0,jsx_runtime.jsx)(_components.code, {
        className: "language-cpp",
        children: "      template <typename ObjectType>\n      class TAttribute\n"
      })
    }), "\n", (0,jsx_runtime.jsxs)(_components.ul, {
      children: ["\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["Classes that inherit from ", (0,jsx_runtime.jsx)(_components.a, {
          href: "https://dev.epicgames.com/documentation/en-us/unreal-engine/objects-in-unreal-engine",
          children: "UObject"
        }), " are prefixed by U."]
      }), "\n"]
    }), "\n", (0,jsx_runtime.jsx)(_components.pre, {
      children: (0,jsx_runtime.jsx)(_components.code, {
        className: "language-cpp",
        children: "      class UActorComponent\n"
      })
    }), "\n", (0,jsx_runtime.jsxs)(_components.ul, {
      children: ["\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["Classes that inherit from ", (0,jsx_runtime.jsx)(_components.a, {
          href: "https://dev.epicgames.com/documentation/en-us/unreal-engine/actors-in-unreal-engine",
          children: "AActor"
        }), " are prefixed by A."]
      }), "\n"]
    }), "\n", (0,jsx_runtime.jsx)(_components.pre, {
      children: (0,jsx_runtime.jsx)(_components.code, {
        className: "language-cpp",
        children: "      class AActor\n"
      })
    }), "\n", (0,jsx_runtime.jsxs)(_components.ul, {
      children: ["\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["Classes that inherit from ", (0,jsx_runtime.jsx)(_components.a, {
          href: "https://dev.epicgames.com/documentation/en-us/unreal-engine/slate-user-interface-programming-framework-for-unreal-engine",
          children: "SWidget"
        }), " are prefixed by S."]
      }), "\n"]
    }), "\n", (0,jsx_runtime.jsx)(_components.pre, {
      children: (0,jsx_runtime.jsx)(_components.code, {
        className: "language-cpp",
        children: "      class SCompoundWidget\n"
      })
    }), "\n", (0,jsx_runtime.jsxs)(_components.ul, {
      children: ["\n", (0,jsx_runtime.jsx)(_components.li, {
        children: "Classes that are abstract interfaces are prefixed by I."
      }), "\n"]
    }), "\n", (0,jsx_runtime.jsx)(_components.pre, {
      children: (0,jsx_runtime.jsx)(_components.code, {
        className: "language-cpp",
        children: "      class IAnalyticsProvider\n"
      })
    }), "\n", (0,jsx_runtime.jsxs)(_components.ul, {
      children: ["\n", (0,jsx_runtime.jsx)(_components.li, {
        children: "Epic's concept-alike struct types are prefixed by C."
      }), "\n"]
    }), "\n", (0,jsx_runtime.jsx)(_components.pre, {
      children: (0,jsx_runtime.jsx)(_components.code, {
        className: "language-cpp",
        children: "      struct CStaticClassProvider\n      {\n          template <typename T>\n          auto Requires(UClass*& ClassRef) -> decltype(\n              ClassRef = T::StaticClass()\n          );\n      };\n"
      })
    }), "\n", (0,jsx_runtime.jsxs)(_components.ul, {
      children: ["\n", (0,jsx_runtime.jsx)(_components.li, {
        children: "Enums are prefixed by E."
      }), "\n"]
    }), "\n", (0,jsx_runtime.jsx)(_components.pre, {
      children: (0,jsx_runtime.jsx)(_components.code, {
        className: "language-cpp",
        children: "     enum class EColorBits\n     {\n         ECB_Red,\n         ECB_Green,\n         ECB_Blue\n     };\n"
      })
    }), "\n", (0,jsx_runtime.jsxs)(_components.ul, {
      children: ["\n", (0,jsx_runtime.jsx)(_components.li, {
        children: "Boolean variables must be prefixed by b."
      }), "\n"]
    }), "\n", (0,jsx_runtime.jsx)(_components.pre, {
      children: (0,jsx_runtime.jsx)(_components.code, {
        className: "language-cpp",
        children: "     bPendingDestruction\n     bHasFadedIn\n"
      })
    }), "\n", (0,jsx_runtime.jsxs)(_components.ul, {
      children: ["\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsx)(_components.p, {
          children: "Most other classes are prefixed by F, though some subsystems use other letters."
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsx)(_components.p, {
          children: "Typedefs should be prefixed by whatever is appropriate for that type, such as:"
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsx)(_components.p, {
          children: "F for typedef of a struct"
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsxs)(_components.p, {
          children: ["U for typedef of a ", (0,jsx_runtime.jsx)(_components.code, {
            children: "UObject"
          })]
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsx)(_components.p, {
          children: "A typedef of a particular template instantiation is no longer a template and should be prefixed accordingly."
        }), "\n"]
      }), "\n"]
    }), "\n", (0,jsx_runtime.jsx)(_components.pre, {
      children: (0,jsx_runtime.jsx)(_components.code, {
        className: "language-cpp",
        children: "     typedef TArray<FMytype> FArrayOfMyTypes;\n"
      })
    }), "\n", (0,jsx_runtime.jsxs)(_components.ul, {
      children: ["\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsx)(_components.p, {
          children: "Prefixes are omitted in C#."
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsx)(_components.p, {
          children: "Unreal Header Tool requires the correct prefixes in most cases, so it's important to provide them."
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsx)(_components.p, {
          children: "Type template parameters and nested type aliases based on those template parameters are not subject to the above prefix rules, as the type category is unknown."
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsx)(_components.p, {
          children: "Prefer a Type suffix after a descriptive term."
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsx)(_components.p, {
          children: "Disambiguate template parameters from aliases by using an In prefix:"
        }), "\n"]
      }), "\n"]
    }), "\n", (0,jsx_runtime.jsx)(_components.pre, {
      children: (0,jsx_runtime.jsx)(_components.code, {
        className: "language-cpp",
        children: "     template <typename InElementType>\n     class TContainer\n     {\n     public:\n         using ElementType = InElementType;\n     };\n"
      })
    }), "\n", (0,jsx_runtime.jsxs)(_components.ul, {
      children: ["\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsx)(_components.p, {
          children: "Type and variable names are nouns."
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsx)(_components.p, {
          children: "Method names are verbs that either describe the method's effect, or the return value of a method without an effect."
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsxs)(_components.p, {
          children: ["Macro names should be fully capitalized with words separated by underscores, and prefixed with ", (0,jsx_runtime.jsx)(_components.code, {
            children: "UE_"
          }), "."]
        }), "\n"]
      }), "\n"]
    }), "\n", (0,jsx_runtime.jsx)(_components.pre, {
      children: (0,jsx_runtime.jsx)(_components.code, {
        className: "language-cpp",
        children: "     #define UE_AUDIT_SPRITER_IMPORT\n"
      })
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "Variable, method, and class names should be:"
    }), "\n", (0,jsx_runtime.jsxs)(_components.ul, {
      children: ["\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsx)(_components.p, {
          children: "Clear"
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsx)(_components.p, {
          children: "Unambiguous"
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsx)(_components.p, {
          children: "Descriptive"
        }), "\n"]
      }), "\n"]
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "The greater the scope of the name, the greater the importance of a good, descriptive name. Avoid over-abbreviation."
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "All variables should be declared on their own line so that you can provide comment on the meaning of each variable."
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "The JavaDocs style requires it."
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "You can use multi-line or single-line comments before a variable Blank lines are optional for grouping variables."
    }), "\n", (0,jsx_runtime.jsxs)(_components.p, {
      children: ["All functions that return a bool should ask a true/false question, such as ", (0,jsx_runtime.jsx)(_components.code, {
        children: "IsVisible()"
      }), " or ", (0,jsx_runtime.jsx)(_components.code, {
        children: "ShouldClearBuffer()"
      }), "."]
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "A procedure (a function with no return value) should use a strong verb followed by an Object. An exception is, if the Object of the method is the Object it is in. In this case, the Object is understood from context. Names to avoid include those beginning with \"Handle\" and \"Process\" because the verbs are ambiguous."
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "We encourage you to prefix function parameter names with \"Out\" if:"
    }), "\n", (0,jsx_runtime.jsxs)(_components.ul, {
      children: ["\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsx)(_components.p, {
          children: "The function parameters are passed by reference."
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsx)(_components.p, {
          children: "The function is expected to write to that value."
        }), "\n"]
      }), "\n"]
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "This makes it obvious that the value passed in this argument is replaced by the function."
    }), "\n", (0,jsx_runtime.jsxs)(_components.p, {
      children: ["If an In or Out parameter is also a boolean, put \"b\" before the In/Out prefix, such as ", (0,jsx_runtime.jsx)(_components.code, {
        children: "bOutResult"
      }), "."]
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "Functions that return a value should describe the return value. The name should make clear what value the function returns. This is particularly important for boolean functions. Consider the following two example methods:"
    }), "\n", (0,jsx_runtime.jsx)(_components.pre, {
      children: (0,jsx_runtime.jsx)(_components.code, {
        className: "language-cpp",
        children: "// what does true mean?\nbool CheckTea(FTea Tea);\n\n// name makes it clear true means tea is fresh\nbool IsTeaFresh(FTea Tea);\n\nfloat TeaWeight;\nint32 TeaCount;\nbool bDoesTeaStink;\nFName TeaName;\nFString TeaFriendlyName;\nUClass* TeaClass;\nUSoundCue* TeaSound;\nUTexture* TeaTexture;\n"
      })
    }), "\n", (0,jsx_runtime.jsx)(_components.h2, {
      id: "inclusive-word-choice",
      children: "Inclusive Word Choice"
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "When you work in the Unreal Engine codebase, we encourage you to strive to use respectful, inclusive, and professional language."
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "Word choice applies when you:"
    }), "\n", (0,jsx_runtime.jsxs)(_components.ul, {
      children: ["\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsx)(_components.p, {
          children: "name classes."
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsx)(_components.p, {
          children: "functions."
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsx)(_components.p, {
          children: "data structures."
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsx)(_components.p, {
          children: "types."
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsx)(_components.p, {
          children: "variables."
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsx)(_components.p, {
          children: "files and folders."
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsx)(_components.p, {
          children: "plugins."
        }), "\n"]
      }), "\n"]
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "It applies when you write snippets of user-facing text for the UI, error messages, and notifications. It also applies when writing about code, such as in comments and changelist descriptions."
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "The following sections provide guidance and suggestions to help you choose words and names that are respectful and appropriate for all situations and audiences, and be a more effective communicator."
    }), "\n", (0,jsx_runtime.jsx)(_components.h3, {
      id: "racial-ethnic-and-religious-inclusiveness",
      children: "Racial, ethnic, and religious inclusiveness"
    }), "\n", (0,jsx_runtime.jsxs)(_components.ul, {
      children: ["\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsxs)(_components.p, {
          children: ["Do not use metaphors or similes that reinforce stereotypes. Examples include contrast black and white or ", (0,jsx_runtime.jsx)(_components.em, {
            children: "blacklist"
          }), " and ", (0,jsx_runtime.jsx)(_components.em, {
            children: "whitelist"
          }), "."]
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsxs)(_components.p, {
          children: ["Do not use words that refer to historical trauma or lived experience of discrimination. Examples include ", (0,jsx_runtime.jsx)(_components.em, {
            children: "slave"
          }), ", ", (0,jsx_runtime.jsx)(_components.em, {
            children: "master"
          }), ", and ", (0,jsx_runtime.jsx)(_components.em, {
            children: "nuke"
          }), "."]
        }), "\n"]
      }), "\n"]
    }), "\n", (0,jsx_runtime.jsx)(_components.h3, {
      id: "gender-inclusiveness",
      children: "Gender inclusiveness"
    }), "\n", (0,jsx_runtime.jsxs)(_components.ul, {
      children: ["\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsxs)(_components.p, {
          children: ["Refer to hypothetical people as ", (0,jsx_runtime.jsx)(_components.em, {
            children: "they"
          }), ", ", (0,jsx_runtime.jsx)(_components.em, {
            children: "them"
          }), ", and ", (0,jsx_runtime.jsx)(_components.em, {
            children: "their"
          }), ", even in the singular."]
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsxs)(_components.p, {
          children: ["Refer to anything that is not a person as ", (0,jsx_runtime.jsx)(_components.em, {
            children: "it"
          }), " and ", (0,jsx_runtime.jsx)(_components.em, {
            children: "its"
          }), ". For example, a module, plugin, function, client, server, or any other software or hardware component."]
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsx)(_components.p, {
          children: "Do not assign a gender to anything that doesn't have one."
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsxs)(_components.p, {
          children: ["Do not use collective nouns like ", (0,jsx_runtime.jsx)(_components.em, {
            children: "guys"
          }), " that assume gender."]
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsxs)(_components.p, {
          children: ["Avoid colloquial phrases that contain arbitrary genders, like \"a poor ", (0,jsx_runtime.jsx)(_components.em, {
            children: "man"
          }), "'s X\"."]
        }), "\n"]
      }), "\n"]
    }), "\n", (0,jsx_runtime.jsx)(_components.h3, {
      id: "slang",
      children: "Slang"
    }), "\n", (0,jsx_runtime.jsxs)(_components.ul, {
      children: ["\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsx)(_components.p, {
          children: "Remember that your words are being read by a global audience that may not share the same idioms and attitudes, and who might not understand the same cultural references."
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsx)(_components.p, {
          children: "Avoid slang and colloquialisms, even if you think they are funny or harmless. These may be hard to understand for people whose first language is not English, and might not translate well."
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsx)(_components.p, {
          children: "Do not use profanity."
        }), "\n"]
      }), "\n"]
    }), "\n", (0,jsx_runtime.jsx)(_components.h3, {
      id: "overloaded-words",
      children: "Overloaded Words"
    }), "\n", (0,jsx_runtime.jsxs)(_components.ul, {
      children: ["\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["Many terms that we use for their technical meanings also have other meanings outside of technology. Examples include ", (0,jsx_runtime.jsx)(_components.em, {
          children: "abort"
        }), ", ", (0,jsx_runtime.jsx)(_components.em, {
          children: "execute"
        }), ", or ", (0,jsx_runtime.jsx)(_components.em, {
          children: "native"
        }), ". When you use words like these, always be precise and examine the context in which they appear."]
      }), "\n"]
    }), "\n", (0,jsx_runtime.jsx)(_components.h3, {
      id: "word-list",
      children: "Word List"
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "The following list identifies some terminology that we have used in the Unreal codebase in the past, but that we believe should be replaced with better alternatives:"
    }), "\n", (0,jsx_runtime.jsxs)(_components.table, {
      children: [(0,jsx_runtime.jsx)(_components.thead, {
        children: (0,jsx_runtime.jsxs)(_components.tr, {
          children: [(0,jsx_runtime.jsx)(_components.th, {
            children: "Word Name"
          }), (0,jsx_runtime.jsx)(_components.th, {
            children: "Alternative Word Name"
          })]
        })
      }), (0,jsx_runtime.jsxs)(_components.tbody, {
        children: [(0,jsx_runtime.jsxs)(_components.tr, {
          children: [(0,jsx_runtime.jsx)(_components.td, {
            children: "Blacklist"
          }), (0,jsx_runtime.jsxs)(_components.td, {
            children: [(0,jsx_runtime.jsx)(_components.code, {
              children: "_deny list_"
            }), ", ", (0,jsx_runtime.jsx)(_components.code, {
              children: "_block list_"
            }), ",", (0,jsx_runtime.jsx)(_components.code, {
              children: "_exclude list_"
            }), ", ", (0,jsx_runtime.jsx)(_components.code, {
              children: "_avoid list_"
            }), ",", (0,jsx_runtime.jsx)(_components.code, {
              children: "_unapproved list_"
            }), ",", (0,jsx_runtime.jsx)(_components.code, {
              children: "_forbidden list_"
            }), ",", (0,jsx_runtime.jsx)(_components.code, {
              children: "_permission list_"
            })]
          })]
        }), (0,jsx_runtime.jsxs)(_components.tr, {
          children: [(0,jsx_runtime.jsx)(_components.td, {
            children: "Whitelist"
          }), (0,jsx_runtime.jsxs)(_components.td, {
            children: ["allow list_, ", (0,jsx_runtime.jsx)(_components.em, {
              children: "include list"
            }), ", ", (0,jsx_runtime.jsx)(_components.em, {
              children: "trust list"
            }), ", ", (0,jsx_runtime.jsx)(_components.em, {
              children: "safe list"
            }), ", ", (0,jsx_runtime.jsx)(_components.em, {
              children: "prefer list"
            }), ", ", (0,jsx_runtime.jsx)(_components.em, {
              children: "approved list"
            }), ", ", (0,jsx_runtime.jsx)(_components.em, {
              children: "permission list"
            })]
          })]
        }), (0,jsx_runtime.jsxs)(_components.tr, {
          children: [(0,jsx_runtime.jsx)(_components.td, {
            children: "Master"
          }), (0,jsx_runtime.jsxs)(_components.td, {
            children: [(0,jsx_runtime.jsx)(_components.em, {
              children: "primary"
            }), ", ", (0,jsx_runtime.jsx)(_components.em, {
              children: "source"
            }), ", ", (0,jsx_runtime.jsx)(_components.em, {
              children: "controller"
            }), ", ", (0,jsx_runtime.jsx)(_components.em, {
              children: "template"
            }), ", ", (0,jsx_runtime.jsx)(_components.em, {
              children: "reference"
            }), ", ", (0,jsx_runtime.jsx)(_components.em, {
              children: "main"
            }), ", ", (0,jsx_runtime.jsx)(_components.em, {
              children: "leader"
            }), ", ", (0,jsx_runtime.jsx)(_components.em, {
              children: "original"
            }), ", ", (0,jsx_runtime.jsx)(_components.em, {
              children: "base"
            })]
          })]
        }), (0,jsx_runtime.jsxs)(_components.tr, {
          children: [(0,jsx_runtime.jsx)(_components.td, {
            children: "Slave"
          }), (0,jsx_runtime.jsxs)(_components.td, {
            children: [(0,jsx_runtime.jsx)(_components.em, {
              children: "secondary"
            }), ", ", (0,jsx_runtime.jsx)(_components.em, {
              children: "replica"
            }), ", ", (0,jsx_runtime.jsx)(_components.em, {
              children: "agent"
            }), ", ", (0,jsx_runtime.jsx)(_components.em, {
              children: "follower"
            }), ", ", (0,jsx_runtime.jsx)(_components.em, {
              children: "worker"
            }), ", ", (0,jsx_runtime.jsx)(_components.em, {
              children: "cluster node"
            }), ", ", (0,jsx_runtime.jsx)(_components.em, {
              children: "locked"
            }), ", ", (0,jsx_runtime.jsx)(_components.em, {
              children: "linked"
            }), ", ", (0,jsx_runtime.jsx)(_components.em, {
              children: "synchronized"
            })]
          })]
        })]
      })]
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "We are actively working to bring our code in line with the principles laid out above."
    }), "\n", (0,jsx_runtime.jsx)(_components.h2, {
      id: "portable-c-code",
      children: "Portable C++ code"
    }), "\n", (0,jsx_runtime.jsxs)(_components.p, {
      children: ["The ", (0,jsx_runtime.jsx)(_components.code, {
        children: "int"
      }), " and unsigned ", (0,jsx_runtime.jsx)(_components.code, {
        children: "int"
      }), " types vary in size across platforms. They are guaranteed to be at least 32 bits in width and are acceptable in code when the integer width is unimportant. Explicitly-sized types are used in serialized or replicated formats."]
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "Below is a list of common types:"
    }), "\n", (0,jsx_runtime.jsxs)(_components.ul, {
      children: ["\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsxs)(_components.p, {
          children: [(0,jsx_runtime.jsx)(_components.code, {
            children: "bool"
          }), " for boolean values (NEVER assume the size of bool). ", (0,jsx_runtime.jsx)(_components.code, {
            children: "BOOL"
          }), " will not compile."]
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsxs)(_components.p, {
          children: [(0,jsx_runtime.jsx)(_components.code, {
            children: "TCHAR"
          }), " for a character (NEVER assume the size of TCHAR)."]
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsxs)(_components.p, {
          children: [(0,jsx_runtime.jsx)(_components.code, {
            children: "uint8"
          }), " for unsigned bytes (1 byte)."]
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsxs)(_components.p, {
          children: [(0,jsx_runtime.jsx)(_components.code, {
            children: "int8"
          }), " for signed bytes (1 byte)."]
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsxs)(_components.p, {
          children: [(0,jsx_runtime.jsx)(_components.code, {
            children: "uint16"
          }), " for unsigned shorts (2 bytes)."]
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsxs)(_components.p, {
          children: [(0,jsx_runtime.jsx)(_components.code, {
            children: "int16"
          }), " for signed shorts (2 bytes)."]
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsxs)(_components.p, {
          children: [(0,jsx_runtime.jsx)(_components.code, {
            children: "uint32"
          }), " for unsigned ints (4 bytes)."]
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsxs)(_components.p, {
          children: [(0,jsx_runtime.jsx)(_components.code, {
            children: "int32"
          }), " for signed ints (4 bytes)."]
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsxs)(_components.p, {
          children: [(0,jsx_runtime.jsx)(_components.code, {
            children: "uint64"
          }), " for unsigned quad words (8 bytes)."]
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsxs)(_components.p, {
          children: [(0,jsx_runtime.jsx)(_components.code, {
            children: "int64"
          }), " for signed quad words (8 bytes)."]
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsxs)(_components.p, {
          children: [(0,jsx_runtime.jsx)(_components.code, {
            children: "float"
          }), " for single precision floating point (4 bytes)."]
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsxs)(_components.p, {
          children: [(0,jsx_runtime.jsx)(_components.code, {
            children: "double"
          }), " for double precision floating point (8 bytes)."]
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsxs)(_components.p, {
          children: [(0,jsx_runtime.jsx)(_components.code, {
            children: "PTRINT"
          }), " for an integer that may hold a pointer (NEVER assume the size of PTRINT)."]
        }), "\n"]
      }), "\n"]
    }), "\n", (0,jsx_runtime.jsx)(_components.h2, {
      id: "use-of-standard-libraries",
      children: "Use of standard libraries"
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "Historically, UE has avoided direct use of the C and C++ standard libraries for the following reasons:"
    }), "\n", (0,jsx_runtime.jsxs)(_components.ul, {
      children: ["\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsx)(_components.p, {
          children: "Replace slow implementations with our own that provide additional control over memory allocation."
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsx)(_components.p, {
          children: "Add new functionality before it's widely available, such as:"
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsx)(_components.p, {
          children: "Making desirable, but non-standard, behavioral changes."
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsx)(_components.p, {
          children: "Having consistent syntax across the codebase."
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsx)(_components.p, {
          children: "Avoiding constructs which are incompatible with UE's idioms."
        }), "\n"]
      }), "\n"]
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "However, the standard library has matured and includes functionality that we don't want to wrap with an abstraction layer or reimplement ourselves."
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "When there is a choice between a standard library feature instead of our own, you should prefer the option that gives superior results. It's also important to remember that consistency is valued. If a legacy UE implementation is no longer serving a purpose, we may choose to deprecate it and migrate all usage toward the standard library."
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "Avoid mixing UE idioms and standard library idioms in the same API. The following table lists common idioms along with recommendations on when to use them."
    }), "\n", (0,jsx_runtime.jsxs)(_components.table, {
      children: [(0,jsx_runtime.jsx)(_components.thead, {
        children: (0,jsx_runtime.jsxs)(_components.tr, {
          children: [(0,jsx_runtime.jsx)(_components.th, {
            children: "Idiom"
          }), (0,jsx_runtime.jsx)(_components.th, {
            children: "Description"
          })]
        })
      }), (0,jsx_runtime.jsxs)(_components.tbody, {
        children: [(0,jsx_runtime.jsxs)(_components.tr, {
          children: [(0,jsx_runtime.jsx)(_components.td, {
            children: "``"
          }), (0,jsx_runtime.jsxs)(_components.td, {
            children: ["The atomic idiom should be used in new code and old migrated when touched. Atomics are expected to be implemented fully and efficiently on all supported platforms. Our own ", (0,jsx_runtime.jsx)(_components.code, {
              children: "TAtomic"
            }), " is only partially implemented, and it isn't in our interest to maintain and improve it."]
          })]
        }), (0,jsx_runtime.jsxs)(_components.tr, {
          children: [(0,jsx_runtime.jsx)(_components.td, {
            children: "``"
          }), (0,jsx_runtime.jsxs)(_components.td, {
            children: ["The type traits idiom should be used where there's overlap between a legacy UE trait and a standard trait. Traits are often implemented as compiler intrinsics for correctness, and compilers can have knowledge of the standard traits and select faster compilation paths instead of treating them as plain C++. One concern is that our traits typically have an upper case ", (0,jsx_runtime.jsx)(_components.code, {
              children: "Value"
            }), " static or ", (0,jsx_runtime.jsx)(_components.code, {
              children: "Type"
            }), " typedef, whereas standard traits are expected to use ", (0,jsx_runtime.jsx)(_components.code, {
              children: "value"
            }), " and ", (0,jsx_runtime.jsx)(_components.code, {
              children: "type"
            }), ". This is an important distinction, as a particular syntax is expected by compositional traits, for example ", (0,jsx_runtime.jsx)(_components.code, {
              children: "std::conjunction"
            }), ". New traits we add should be written with lowercase ", (0,jsx_runtime.jsx)(_components.code, {
              children: "value"
            }), " or ", (0,jsx_runtime.jsx)(_components.code, {
              children: "type"
            }), " to support composition. Existing traits should be updated to support either case."]
          })]
        }), (0,jsx_runtime.jsxs)(_components.tr, {
          children: [(0,jsx_runtime.jsx)(_components.td, {
            children: "``"
          }), (0,jsx_runtime.jsx)(_components.td, {
            children: "The initializer list idiom must be used to support braced initializer syntax. This is a case where the language and the standard libraries overlap. There is no alternative if you want to support it."
          })]
        }), (0,jsx_runtime.jsxs)(_components.tr, {
          children: [(0,jsx_runtime.jsx)(_components.td, {
            children: "``"
          }), (0,jsx_runtime.jsx)(_components.td, {
            children: "The regex idiom may be used directly, but its use should be encapsulated within editor-only code. We have no plans to implement our own regex solution."
          })]
        }), (0,jsx_runtime.jsxs)(_components.tr, {
          children: [(0,jsx_runtime.jsx)(_components.td, {
            children: "``"
          }), (0,jsx_runtime.jsxs)(_components.td, {
            children: [(0,jsx_runtime.jsx)(_components.code, {
              children: "std::numeric_limits"
            }), " can be used in its entirety."]
          })]
        }), (0,jsx_runtime.jsxs)(_components.tr, {
          children: [(0,jsx_runtime.jsx)(_components.td, {
            children: "``"
          }), (0,jsx_runtime.jsx)(_components.td, {
            children: "All floating point functions from this header may be used."
          })]
        }), (0,jsx_runtime.jsxs)(_components.tr, {
          children: [(0,jsx_runtime.jsxs)(_components.td, {
            children: ["``: ", (0,jsx_runtime.jsx)(_components.code, {
              children: "memcpy()"
            }), " and ", (0,jsx_runtime.jsx)(_components.code, {
              children: "memset()"
            })]
          }), (0,jsx_runtime.jsxs)(_components.td, {
            children: ["These idioms may be used instead of ", (0,jsx_runtime.jsx)(_components.code, {
              children: "FMemory::Memcpy"
            }), " and ", (0,jsx_runtime.jsx)(_components.code, {
              children: "FMemory::Memset"
            }), " respectively, when they have a demonstrable performance benefit."]
          })]
        })]
      })]
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "Standard containers and strings should be avoided except in interop code."
    }), "\n", (0,jsx_runtime.jsx)(_components.h2, {
      id: "comments",
      children: "Comments"
    }), "\n", (0,jsx_runtime.jsxs)(_components.p, {
      children: ["Comments are communication and communication is vital. The following sections detail some important things to keep in mind about comments (from Kernighan & Pike ", (0,jsx_runtime.jsx)(_components.em, {
        children: "The Practice of Programming"
      }), ")."]
    }), "\n", (0,jsx_runtime.jsx)(_components.h3, {
      id: "guidelines",
      children: "Guidelines"
    }), "\n", (0,jsx_runtime.jsxs)(_components.ul, {
      children: ["\n", (0,jsx_runtime.jsx)(_components.li, {
        children: "Write self-documenting code. For example:"
      }), "\n"]
    }), "\n", (0,jsx_runtime.jsx)(_components.pre, {
      children: (0,jsx_runtime.jsx)(_components.code, {
        className: "language-cpp",
        children: "    // Bad:\n    t = s + l - b;\n\n    // Good:\n    TotalLeaves = SmallLeaves + LargeLeaves - SmallAndLargeLeaves;\n"
      })
    }), "\n", (0,jsx_runtime.jsxs)(_components.ul, {
      children: ["\n", (0,jsx_runtime.jsx)(_components.li, {
        children: "Write useful comments. For example:"
      }), "\n"]
    }), "\n", (0,jsx_runtime.jsx)(_components.pre, {
      children: (0,jsx_runtime.jsx)(_components.code, {
        className: "language-cpp",
        children: "    // Bad:\n    // increment Leaves\n    ++Leaves;\n\n    // Good:\n    // we know there is another tea leaf\n    ++Leaves;\n"
      })
    }), "\n", (0,jsx_runtime.jsxs)(_components.ul, {
      children: ["\n", (0,jsx_runtime.jsx)(_components.li, {
        children: "Do not over comment bad code — rewrite it instead. For example:"
      }), "\n"]
    }), "\n", (0,jsx_runtime.jsx)(_components.pre, {
      children: (0,jsx_runtime.jsx)(_components.code, {
        className: "language-cpp",
        children: "    // Bad:\n    // total number of leaves is sum of\n    // small and large leaves less the\n    // number of leaves that are both\n    t = s + l - b;\n\n    // Good:\n    TotalLeaves = SmallLeaves + LargeLeaves - SmallAndLargeLeaves;\n"
      })
    }), "\n", (0,jsx_runtime.jsxs)(_components.ul, {
      children: ["\n", (0,jsx_runtime.jsx)(_components.li, {
        children: "Do not contradict the code. For example:"
      }), "\n"]
    }), "\n", (0,jsx_runtime.jsx)(_components.pre, {
      children: (0,jsx_runtime.jsx)(_components.code, {
        className: "language-cpp",
        children: "    // Bad:\n    // never increment Leaves!\n    ++Leaves;\n\n    // Good:\n    // we know there is another tea leaf\n    ++Leaves;\n"
      })
    }), "\n", (0,jsx_runtime.jsx)(_components.h3, {
      id: "const-correctness",
      children: "Const Correctness"
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "Const is documentation as much as it is a compiler directive. All code should strive to be const-correct. This includes the following guidelines:"
    }), "\n", (0,jsx_runtime.jsxs)(_components.ul, {
      children: ["\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsx)(_components.p, {
          children: "Pass function arguments by const pointer or reference if those arguments are not intended to be modified by the function."
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsx)(_components.p, {
          children: "Flag methods as const if they do not modify the object."
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsx)(_components.p, {
          children: "Use const iteration over containers if the loop isn't intended to modify the container."
        }), "\n"]
      }), "\n"]
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "Const Example:"
    }), "\n", (0,jsx_runtime.jsx)(_components.pre, {
      children: (0,jsx_runtime.jsx)(_components.code, {
        className: "language-cpp",
        children: "void SomeMutatingOperation(FThing& OutResult, const TArray<Int32>& InArray)\n{\n    // InArray will not be modified here, but OutResult probably will be\n}\n\nvoid FThing::SomeNonMutatingOperation() const\n{\n    // This code will not modify the FThing it is invoked on\n}\n\nTArray<FString> StringArray;\nfor (const FString& : StringArray)\n{\n    // The body of this loop will not modify StringArray\n}\n"
      })
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "Const is also preferred for by-value function parameters and locals. This tells the reader that the variable will not be modified in the body of the function, which makes it easier to understand. If you do this, make sure that the declaration and the definition match, as this can affect the JavaDoc process."
    }), "\n", (0,jsx_runtime.jsx)(_components.pre, {
      children: (0,jsx_runtime.jsx)(_components.code, {
        className: "language-cpp",
        children: "void AddSomeThings(const int32 Count);\n\nvoid AddSomeThings(const int32 Count)\n{\n    const int32 CountPlusOne = Count + 1;\n    // Neither Count nor CountPlusOne can be changed during the body of the function\n}\n"
      })
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "One exception to this is pass-by-value parameters, which are moved into a container. For more information, see the \"Move semantics\" section on this page."
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "Example:"
    }), "\n", (0,jsx_runtime.jsx)(_components.pre, {
      children: (0,jsx_runtime.jsx)(_components.code, {
        className: "language-cpp",
        children: "void FBlah::SetMemberArray(TArray<FString> InNewArray)\n{\n    MemberArray = MoveTemp(InNewArray);\n}\n"
      })
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "Put the const keyword on the end when making a pointer itself const (rather than what it points to). References can't be \"reassigned\" anyway, and so can't be made const in the same way."
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "Example:"
    }), "\n", (0,jsx_runtime.jsx)(_components.pre, {
      children: (0,jsx_runtime.jsx)(_components.code, {
        className: "language-cpp",
        children: "// Const pointer to non-const object - pointer cannot be reassigned, but T can still be modified\nT* const Ptr = ...;\n\n// Illegal\nT& const Ref = ...;\n"
      })
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "Never use const on a return type. This inhibits move semantics for complex types, and will give compile warnings for built-in types. This rule only applies to the return type itself, not the target type of a pointer or reference being returned."
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "Example:"
    }), "\n", (0,jsx_runtime.jsx)(_components.pre, {
      children: (0,jsx_runtime.jsx)(_components.code, {
        className: "language-cpp",
        children: "// Bad - returning a const array\nconst TArray<FString> GetSomeArray();\n\n// Fine - returning a reference to a const array\nconst TArray<FString>& GetSomeArray();\n\n// Fine - returning a pointer to a const array\nconst TArray<FString>* GetSomeArray();\n\n// Bad - returning a const pointer to a const array\nconst TArray<FString>* const GetSomeArray();\n"
      })
    }), "\n", (0,jsx_runtime.jsx)(_components.h3, {
      id: "example-formatting",
      children: "Example Formatting"
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "We use a system based on JavaDoc to extract comments from the code and build documentation automatically, therefore we recommend specific comment formatting rules."
    }), "\n", (0,jsx_runtime.jsxs)(_components.p, {
      children: ["The following example demonstrates the format of ", (0,jsx_runtime.jsx)(_components.strong, {
        children: "class"
      }), ", ", (0,jsx_runtime.jsx)(_components.strong, {
        children: "method"
      }), ", and ", (0,jsx_runtime.jsx)(_components.strong, {
        children: "variable"
      }), " comments. Remember that comments should augment the code. Code documents the implementation while comments document the intent. Make sure to update comments when you change the intent of a piece of code."]
    }), "\n", (0,jsx_runtime.jsxs)(_components.p, {
      children: ["Note that two different parameter comment styles are supported, shown by the ", (0,jsx_runtime.jsx)(_components.code, {
        children: "Steep"
      }), " and ", (0,jsx_runtime.jsx)(_components.code, {
        children: "Sweeten"
      }), " methods. The ", (0,jsx_runtime.jsx)(_components.code, {
        children: "@param"
      }), " style used by ", (0,jsx_runtime.jsx)(_components.code, {
        children: "Steep"
      }), " is the traditional multi-line style. For simple functions, it can be clearer to integrate the parameter and return value documentation into the descriptive comment for the function. This is demonstrated in the ", (0,jsx_runtime.jsx)(_components.code, {
        children: "Sweeten"
      }), " example. Special comment tags like ", (0,jsx_runtime.jsx)(_components.code, {
        children: "@see"
      }), " or ", (0,jsx_runtime.jsx)(_components.code, {
        children: "@return"
      }), " should only be used to start new lines following the primary description."]
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "Method comments should only be included once: where the method is publicly declared. The method comments should only contain information relevant to callers of the method, including any information about overrides of the method that may be relevant to the caller. Details about the implementation of the method and its overrides, that are not relevant to callers, should be commented within the method implementation."
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "Class comments should include:"
    }), "\n", (0,jsx_runtime.jsxs)(_components.ul, {
      children: ["\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsx)(_components.p, {
          children: "A description of the problem this class solves."
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsx)(_components.p, {
          children: "The reason why was this class created."
        }), "\n"]
      }), "\n"]
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "Multi-line method comments should include:"
    }), "\n", (0,jsx_runtime.jsxs)(_components.ul, {
      children: ["\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsxs)(_components.p, {
          children: [(0,jsx_runtime.jsx)(_components.strong, {
            children: "Function purpose"
          }), ": Documents the problem this function solves. As previously stated, comments document intent, and code documents implementation."]
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsxs)(_components.p, {
          children: [(0,jsx_runtime.jsx)(_components.strong, {
            children: "Parameter comments"
          }), ": Each parameter comment should include:"]
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsx)(_components.p, {
          children: "units of measure;"
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsx)(_components.p, {
          children: "the range of expected values;"
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsx)(_components.p, {
          children: "\"impossible\" values;"
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsx)(_components.p, {
          children: "and the meaning of status/error codes."
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsxs)(_components.p, {
          children: [(0,jsx_runtime.jsx)(_components.strong, {
            children: "Return comment"
          }), ": Documents the expected return value, just as an output variable is documented. To avoid redundancy, an explicit ", (0,jsx_runtime.jsx)(_components.code, {
            children: "@return"
          }), " comment should not be used if the sole purpose of the function is to return this value and that is already documented in the function purpose."]
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsxs)(_components.p, {
          children: [(0,jsx_runtime.jsx)(_components.strong, {
            children: "Extra information:"
          }), " ", (0,jsx_runtime.jsx)(_components.code, {
            children: "@warning"
          }), ", ", (0,jsx_runtime.jsx)(_components.code, {
            children: "@note"
          }), ", ", (0,jsx_runtime.jsx)(_components.code, {
            children: "@see"
          }), ", and ", (0,jsx_runtime.jsx)(_components.code, {
            children: "@deprecated"
          }), " can optionally be used to document additional relevant information. Each should be declared on their own line following the rest of the comments."]
        }), "\n"]
      }), "\n"]
    }), "\n", (0,jsx_runtime.jsx)(_components.h2, {
      id: "modern-c-language-syntax",
      children: "Modern C++ Language Syntax"
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "Unreal Engine is built to be massively portable to many C++ compilers, so we are careful to use features that are compatible with the compilers we might be supporting. Sometimes, features are so useful that we will wrap them in macros and use them pervasively. However, we usually wait until all the compilers we support are up to the latest standard."
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "Unreal Engine compiles with a language version of C++20 by default and requires a minimum version of C++20 to build. We use many modern language features that are well-supported across modern compilers. In some cases, we wrap usage of these features in preprocessor conditionals. However, sometimes we decide to avoid certain language features entirely, for portability or other reasons."
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "Unless specified below, as a modern C++ compiler feature we are supporting, you should not use compiler-specific language features unless they are wrapped in preprocessor macros or conditionals and used sparingly."
    }), "\n", (0,jsx_runtime.jsx)(_components.h3, {
      id: "static-assert",
      children: "Static Assert"
    }), "\n", (0,jsx_runtime.jsxs)(_components.p, {
      children: ["The ", (0,jsx_runtime.jsx)(_components.code, {
        children: "static_assert"
      }), " keyword is valid for use where you need a compile-time assertion."]
    }), "\n", (0,jsx_runtime.jsx)(_components.h3, {
      id: "override-and-final",
      children: "Override and Final"
    }), "\n", (0,jsx_runtime.jsxs)(_components.p, {
      children: ["The ", (0,jsx_runtime.jsx)(_components.code, {
        children: "override"
      }), " and ", (0,jsx_runtime.jsx)(_components.code, {
        children: "final"
      }), " keywords are valid for use, and their use is strongly encouraged. There might be many places where these have been omitted, but they will be fixed over time."]
    }), "\n", (0,jsx_runtime.jsx)(_components.h3, {
      id: "nullptr",
      children: "Nullptr"
    }), "\n", (0,jsx_runtime.jsxs)(_components.p, {
      children: ["You should use ", (0,jsx_runtime.jsx)(_components.code, {
        children: "nullptr"
      }), " instead of the C-style ", (0,jsx_runtime.jsx)(_components.code, {
        children: "NULL"
      }), " macro in all cases."]
    }), "\n", (0,jsx_runtime.jsxs)(_components.p, {
      children: ["One exception to this is the use of ", (0,jsx_runtime.jsx)(_components.code, {
        children: "nullptr"
      }), " in C++/CX builds (such as for Xbox One). In this case, the use of ", (0,jsx_runtime.jsx)(_components.code, {
        children: "nullptr"
      }), " is actually the managed null reference type. It is mostly compatible with ", (0,jsx_runtime.jsx)(_components.code, {
        children: "nullptr"
      }), " from native C++ except in its type and some template instantiation contexts, and so you should use the ", (0,jsx_runtime.jsx)(_components.code, {
        children: "TYPE_OF_NULLPTR"
      }), " macro instead of the more usual ", (0,jsx_runtime.jsx)(_components.code, {
        children: "decltype(nullptr)"
      }), " for compatibility."]
    }), "\n", (0,jsx_runtime.jsx)(_components.h3, {
      id: "auto",
      children: "Auto"
    }), "\n", (0,jsx_runtime.jsxs)(_components.p, {
      children: ["You shouldn't use ", (0,jsx_runtime.jsx)(_components.code, {
        children: "auto"
      }), " in C++ code, except for the few exceptions listed below. Always be explicit about the type you're initializing. This means that the type must be plainly visible to the reader. This rule also applies to the use of the ", (0,jsx_runtime.jsx)(_components.code, {
        children: "var"
      }), " keyword in C#."]
    }), "\n", (0,jsx_runtime.jsxs)(_components.p, {
      children: ["C++20's structured binding feature should also not be used, as it is effectively a variadic ", (0,jsx_runtime.jsx)(_components.code, {
        children: "auto"
      }), "."]
    }), "\n", (0,jsx_runtime.jsxs)(_components.p, {
      children: ["Acceptable use of ", (0,jsx_runtime.jsx)(_components.code, {
        children: "auto"
      }), ":"]
    }), "\n", (0,jsx_runtime.jsxs)(_components.ul, {
      children: ["\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsx)(_components.p, {
          children: "When you need to bind a lambda to a variable, as lambda types are not expressible in code."
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsx)(_components.p, {
          children: "For iterator variables, but only where the iterator's type is verbose and would impair readability."
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsx)(_components.p, {
          children: "In template code, where the type of an expression cannot easily be discerned. This is an advanced case."
        }), "\n"]
      }), "\n"]
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "It's very important that types are clearly visible to someone who is reading the code. Even though some IDEs are able to infer the type, doing so relies on the code being in a compilable state. It also won't assist users of merge/diff tools, or when viewing individual source files in isolation, such as on GitHub."
    }), "\n", (0,jsx_runtime.jsxs)(_components.p, {
      children: ["If you're sure you are using ", (0,jsx_runtime.jsx)(_components.code, {
        children: "auto"
      }), " in an acceptable way, always remember to correctly use ", (0,jsx_runtime.jsx)(_components.code, {
        children: "const"
      }), ", ", (0,jsx_runtime.jsx)(_components.code, {
        children: "&"
      }), ", or ", (0,jsx_runtime.jsx)(_components.code, {
        children: "*"
      }), " just like you would with the type name. With ", (0,jsx_runtime.jsx)(_components.code, {
        children: "auto"
      }), ", this will coerce the inferred type to be what you want."]
    }), "\n", (0,jsx_runtime.jsx)(_components.h3, {
      id: "range-based-for",
      children: "Range-Based For"
    }), "\n", (0,jsx_runtime.jsxs)(_components.p, {
      children: ["This is preferred to keep the code easier to understand and more maintainable. When you migrate code that uses old ", (0,jsx_runtime.jsx)(_components.code, {
        children: "TMap"
      }), " iterators, be aware that the old ", (0,jsx_runtime.jsx)(_components.code, {
        children: "Key()"
      }), " and ", (0,jsx_runtime.jsx)(_components.code, {
        children: "Value()"
      }), " functions, which were methods of the iterator type, are now simply ", (0,jsx_runtime.jsx)(_components.code, {
        children: "Key"
      }), " and ", (0,jsx_runtime.jsx)(_components.code, {
        children: "Value"
      }), " fields of the underlying key-value ", (0,jsx_runtime.jsx)(_components.code, {
        children: "TPair"
      }), "."]
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "Example:"
    }), "\n", (0,jsx_runtime.jsx)(_components.pre, {
      children: (0,jsx_runtime.jsx)(_components.code, {
        className: "language-cpp",
        children: "TMap<FString, int32> MyMap;\n\n// Old style\nfor (auto It = MyMap.CreateIterator(); It; ++It)\n{\n    UE_LOG(LogCategory, Log, TEXT(\"Key: %s, Value: %d\"), It.Key(), *It.Value());\n}\n\n// New style\nfor (TPair<FString, int32>& Kvp : MyMap)\n{\n    UE_LOG(LogCategory, Log, TEXT(\"Key: %s, Value: %d\"), *Kvp.Key, Kvp.Value);\n}\n"
      })
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "We also have range replacements for some standalone iterator types."
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "Example:"
    }), "\n", (0,jsx_runtime.jsx)(_components.pre, {
      children: (0,jsx_runtime.jsx)(_components.code, {
        className: "language-cpp",
        children: "// Old style\nfor (TFieldIterator<UProperty> PropertyIt(InStruct, EFieldIteratorFlags::IncludeSuper); PropertyIt; ++PropertyIt)\n{\n    UProperty* Property = *PropertyIt;\n    UE_LOG(LogCategory, Log, TEXT(\"Property name: %s\"), *Property->GetName());\n}\n\n// New style\nfor (UProperty* Property : TFieldRange<UProperty>(InStruct, EFieldIteratorFlags::IncludeSuper))\n{\n    UE_LOG(LogCategory, Log, TEXT(\"Property name: %s\"), *Property->GetName());\n}\n"
      })
    }), "\n", (0,jsx_runtime.jsx)(_components.h3, {
      id: "lambdas-and-anonymous-functions",
      children: "Lambdas and Anonymous Functions"
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "Lambdas can be used freely but come with additional safety concerns. The best lambdas should be no more than a couple of statements in length, particularly when used as part of a larger expression or statement, for example as a predicate in a generic algorithm."
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "Example:"
    }), "\n", (0,jsx_runtime.jsx)(_components.pre, {
      children: (0,jsx_runtime.jsx)(_components.code, {
        className: "language-cpp",
        children: "// Find first Thing whose name contains the word \"Hello\"\nThing* HelloThing = ArrayOfThings.FindByPredicate([](const Thing& Th){ return Th.GetName().Contains(TEXT(\"Hello\")); });\n\n// Sort array in reverse order of name\nAlgo::Sort(ArrayOfThings, [](const Thing& Lhs, const Thing& Rhs){ return Lhs.GetName() > Rhs.GetName(); });|\n"
      })
    }), "\n", (0,jsx_runtime.jsxs)(_components.p, {
      children: ["Be aware that stateful lambdas can't be assigned to function pointers, which we tend to use a lot. Non-trivial lambdas should be documented in the same manner as regular functions. Lambdas can also be used as ", (0,jsx_runtime.jsx)(_components.a, {
        href: "https://dev.epicgames.com/documentation/en-us/unreal-engine/delegates-and-lambda-functions-in-unreal-engine",
        children: "Delegates"
      }), " for deferred execution using functions like ", (0,jsx_runtime.jsx)(_components.code, {
        children: "BindWeakLambda"
      }), " where captured variables function as a payload."]
    }), "\n", (0,jsx_runtime.jsx)(_components.h4, {
      id: "captures-and-return-types",
      children: "Captures and Return Types"
    }), "\n", (0,jsx_runtime.jsxs)(_components.p, {
      children: ["Explicit captures should be used rather than automatic capture (", (0,jsx_runtime.jsx)(_components.code, {
        children: "[&]"
      }), " and ", (0,jsx_runtime.jsx)(_components.code, {
        children: "[=]"
      }), "). This is important for readability, maintainability, safety, and performance reasons, particularly when used with large lambdas and deferred execution."]
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "Explicit captures declare the author's intent; therefore, mistakes are caught during code review. Incorrect captures can cause serious bugs and crashes, which are more likely to become problematic as the code is maintained over time. Here are some additional things to keep in mind about lambda captures:"
    }), "\n", (0,jsx_runtime.jsxs)(_components.ul, {
      children: ["\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsxs)(_components.p, {
          children: ["By-reference capture and by-value capture of pointers (including the ", (0,jsx_runtime.jsx)(_components.code, {
            children: "this"
          }), " pointer) can cause data corruption and crashes if the execution of the lambda is deferred. Local and member variables should never be captured by reference for deferred lambdas."]
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsx)(_components.p, {
          children: "By-value capture can be a performance concern if it makes unnecessary copies for a non-deferred lambda."
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsxs)(_components.p, {
          children: ["Accidentally captured UObject pointers are invisible to the garbage collector. Automatic capture catches ", (0,jsx_runtime.jsx)(_components.code, {
            children: "this"
          }), " implicitly if any member variables are referenced, even though ", (0,jsx_runtime.jsx)(_components.code, {
            children: "[=]"
          }), " gives the impression of the lambda having its own copies of everything."]
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsxs)(_components.p, {
          children: ["Delegate wrappers like ", (0,jsx_runtime.jsx)(_components.code, {
            children: "CreateWeakLambda"
          }), " and ", (0,jsx_runtime.jsx)(_components.code, {
            children: "CreateSPLambda"
          }), " should be used for deferred execution as they will automatically unbind if the UObject or shared pointer are freed. Other shared objects can be captured as TWeakObjectPtr or TWeakPtr and then validated inside the lambda."]
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsx)(_components.p, {
          children: "Any deferred lambda use that does not follow these guidelines must have a comment explaining why the lambda capture is safe."
        }), "\n"]
      }), "\n"]
    }), "\n", (0,jsx_runtime.jsxs)(_components.p, {
      children: ["Explicit return types should be used for large lambdas or when you are returning the result of another function call. These should be considered in the same way as the ", (0,jsx_runtime.jsx)(_components.code, {
        children: "auto"
      }), " keyword."]
    }), "\n", (0,jsx_runtime.jsx)(_components.h3, {
      id: "strongly-typed-enums",
      children: "Strongly-Typed Enums"
    }), "\n", (0,jsx_runtime.jsxs)(_components.p, {
      children: ["Enumerated (Enum) classes are a replacement for old-style namespaced enums, both for regular enums and ", (0,jsx_runtime.jsx)(_components.code, {
        children: "UENUMs"
      }), ". For example:"]
    }), "\n", (0,jsx_runtime.jsx)(_components.pre, {
      children: (0,jsx_runtime.jsx)(_components.code, {
        className: "language-cpp",
        children: "// Old enum\nUENUM()\nnamespace EThing\n{\n    enum Type\n    {\n        Thing1,\n        Thing2\n    };\n}\n\n// New enum\nUENUM()\nenum class EThing : uint8\n{\n    Thing1,\n    Thing2\n}\n"
      })
    }), "\n", (0,jsx_runtime.jsxs)(_components.p, {
      children: ["Enums are supported as ", (0,jsx_runtime.jsx)(_components.code, {
        children: "UPROPERTYs"
      }), ", and replace the old ", (0,jsx_runtime.jsx)(_components.code, {
        children: "TEnumAsByte<>"
      }), " workaround. Enum properties can also be any size, not just bytes:"]
    }), "\n", (0,jsx_runtime.jsx)(_components.pre, {
      children: (0,jsx_runtime.jsx)(_components.code, {
        className: "language-cpp",
        children: "// Old property\nUPROPERTY()\nTEnumAsByte<EThing::Type> MyProperty;\n\n// New property\nUPROPERTY()\nEThing MyProperty;\n"
      })
    }), "\n", (0,jsx_runtime.jsxs)(_components.p, {
      children: ["Enums exposed to Blueprints must continue to be based on ", (0,jsx_runtime.jsx)(_components.code, {
        children: "uint8"
      }), "."]
    }), "\n", (0,jsx_runtime.jsxs)(_components.p, {
      children: ["Enum classes used as flags can take advantage of the ", (0,jsx_runtime.jsx)(_components.code, {
        children: "ENUM_CLASS_FLAGS(EnumType)"
      }), " macro to automatically define all of the bitwise operators:"]
    }), "\n", (0,jsx_runtime.jsx)(_components.pre, {
      children: (0,jsx_runtime.jsx)(_components.code, {
        className: "language-cpp",
        children: "enum class EFlags\n{\n    None = 0x00,\n    Flag1 = 0x01,\n    Flag2 = 0x02,\n    Flag3 = 0x04\n};\n\nENUM_CLASS_FLAGS(EFlags)\n"
      })
    }), "\n", (0,jsx_runtime.jsxs)(_components.p, {
      children: ["The one exception to this is the use of flags in a ", (0,jsx_runtime.jsx)(_components.em, {
        children: "truth"
      }), " context - this is a limitation of the language. Instead, all enum flags should have an enumerator called ", (0,jsx_runtime.jsx)(_components.code, {
        children: "None"
      }), " which is set to 0 for comparisons:"]
    }), "\n", (0,jsx_runtime.jsx)(_components.pre, {
      children: (0,jsx_runtime.jsx)(_components.code, {
        className: "language-cpp",
        children: "// Old\nif (Flags & EFlags::Flag1)\n\n// New\nif ((Flags & EFlags::Flag1) != EFlags::None)\n"
      })
    }), "\n", (0,jsx_runtime.jsx)(_components.h3, {
      id: "move-semantics",
      children: "Move Semantics"
    }), "\n", (0,jsx_runtime.jsxs)(_components.p, {
      children: ["All of the main container types — ", (0,jsx_runtime.jsx)(_components.code, {
        children: "TArray"
      }), ", ", (0,jsx_runtime.jsx)(_components.code, {
        children: "TMap"
      }), ", ", (0,jsx_runtime.jsx)(_components.code, {
        children: "TSet"
      }), ", ", (0,jsx_runtime.jsx)(_components.code, {
        children: "FString"
      }), " — have move constructors and move assignment operators. These are often used automatically when passing or returning these types by value. They can also be explicitly invoked by using ", (0,jsx_runtime.jsx)(_components.code, {
        children: "MoveTemp"
      }), ", UE's equivalent of ", (0,jsx_runtime.jsx)(_components.code, {
        children: "std::move"
      }), "."]
    }), "\n", (0,jsx_runtime.jsxs)(_components.p, {
      children: ["Returning containers or strings by value can be beneficial for expressivity, without the usual cost of temporary copies. Rules around pass-by-value and use of ", (0,jsx_runtime.jsx)(_components.code, {
        children: "MoveTemp"
      }), " are still being established, but can already be found in some optimized areas of the codebase."]
    }), "\n", (0,jsx_runtime.jsx)(_components.h3, {
      id: "default-member-initializers",
      children: "Default Member Initializers"
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "Default member initializers can be used to define the defaults of a class inside the class itself:"
    }), "\n", (0,jsx_runtime.jsx)(_components.pre, {
      children: (0,jsx_runtime.jsx)(_components.code, {
        className: "language-cpp",
        children: "UCLASS()\nclass UTeaOptions : public UObject\n{\n    GENERATED_BODY()\n\npublic:\n    UPROPERTY()\n    int32 MaximumNumberOfCupsPerDay = 10;\n\n    UPROPERTY()\n    float CupWidth = 11.5f;\n\n    UPROPERTY()\n    FString TeaType = TEXT(\"Earl Grey\");\n\n    UPROPERTY()\n    EDrinkingStyle DrinkingStyle = EDrinkingStyle::PinkyExtended;\n};\n"
      })
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "Code written like this has the following benefits:"
    }), "\n", (0,jsx_runtime.jsxs)(_components.ul, {
      children: ["\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsx)(_components.p, {
          children: "It doesn't need to duplicate initializers across multiple constructors."
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsx)(_components.p, {
          children: "It isn't possible to mix the initialization order and declaration order."
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsx)(_components.p, {
          children: "The member type, property flags, and default values are all in one place. This helps readability and maintainability."
        }), "\n"]
      }), "\n"]
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "However, there are also some downsides:"
    }), "\n", (0,jsx_runtime.jsxs)(_components.ul, {
      children: ["\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsx)(_components.p, {
          children: "Any change to the defaults requires a rebuild of all dependent files."
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsx)(_components.p, {
          children: "Headers can't change in patch releases of the engine, so this style can limit the kinds of fixes that are possible."
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsxs)(_components.p, {
          children: ["Some things can't be initialized in this way, such as base classes, ", (0,jsx_runtime.jsx)(_components.code, {
            children: "UObject"
          }), " subobjects, pointers to forward-declared types, values deduced from constructor arguments, and members initialized over multiple steps."]
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsx)(_components.p, {
          children: "Putting some initializers in the header and the rest in constructors in the .cpp file, can reduce readability and maintainability."
        }), "\n"]
      }), "\n"]
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "Use your best judgment when deciding whether to use default member initializers.\nAs a rule of thumb, default member initializers make more sense with in-game code than engine code. Consider using config files for default values."
    }), "\n", (0,jsx_runtime.jsx)(_components.h2, {
      id: "third-party-code",
      children: "Third Party Code"
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "Whenever you modify the code to a library that we use in the engine, be sure to tag your changes with a //@UE5 comment, as well as an explanation of why you made the change. This makes merging the changes into a new version of that library easier, and ensures licensees can easily find any modifications we have made."
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "Any third party code included in the engine should be marked with comments formatted to be easily searchable. For example:"
    }), "\n", (0,jsx_runtime.jsx)(_components.pre, {
      children: (0,jsx_runtime.jsx)(_components.code, {
        className: "language-cpp",
        children: "// @third party code - BEGIN PhysX\n#include <physx.h>\n// @third party code - END PhysX\n// @third party code - BEGIN MSDN SetThreadName\n// [http://msdn.microsoft.com/en-us/library/xcb2z8hs.aspx]\n// Used to set the thread name in the debugger\n...\n//@third party code - END MSDN SetThreadName\n"
      })
    }), "\n", (0,jsx_runtime.jsx)(_components.h2, {
      id: "code-formatting",
      children: "Code Formatting"
    }), "\n", (0,jsx_runtime.jsx)(_components.h3, {
      id: "braces",
      children: "Braces"
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "Brace wars are foul. Epic Games has a long standing usage pattern of putting braces on a new line. Please adhere to this usage, regardless of the size of the function or block. For example:"
    }), "\n", (0,jsx_runtime.jsx)(_components.pre, {
      children: (0,jsx_runtime.jsx)(_components.code, {
        className: "language-cpp",
        children: "// Bad\nint32 GetSize() const { return Size; }\n\n// Good\nint32 GetSize() const\n{\n    return Size;\n}\n"
      })
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "Always include braces in single-statement blocks. For example:"
    }), "\n", (0,jsx_runtime.jsx)(_components.pre, {
      children: (0,jsx_runtime.jsx)(_components.code, {
        className: "language-cpp",
        children: "if (bThing)\n{\n    return;\n}\n"
      })
    }), "\n", (0,jsx_runtime.jsx)(_components.h3, {
      id: "if---else",
      children: "If - Else"
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "Each block of execution in an if-else statement should be in braces. This helps prevent editing mistakes. When braces are not used, someone could unwittingly add another line to an if block. The extra line wouldn't be controlled by the if expression, which would be bad. It's also bad when conditionally compiled items cause if/else statements to break. So always use braces."
    }), "\n", (0,jsx_runtime.jsx)(_components.pre, {
      children: (0,jsx_runtime.jsx)(_components.code, {
        className: "language-cpp",
        children: "if (bHaveUnrealLicense)\n{\n    InsertYourGameHere();\n}\nelse\n{\n    CallMarkRein();\n}\n"
      })
    }), "\n", (0,jsx_runtime.jsxs)(_components.p, {
      children: ["A multi-way if statement should be indented with each ", (0,jsx_runtime.jsx)(_components.code, {
        children: "else if"
      }), " indented the same amount as the first ", (0,jsx_runtime.jsx)(_components.code, {
        children: "if"
      }), "; this makes the structure clear to a reader:"]
    }), "\n", (0,jsx_runtime.jsx)(_components.pre, {
      children: (0,jsx_runtime.jsx)(_components.code, {
        className: "language-cpp",
        children: "if (TannicAcid < 10)\n{\n    UE_LOG(LogCategory, Log, TEXT(\"Low Acid\"));\n}\nelse if (TannicAcid < 100)\n{\n    UE_LOG(LogCategory, Log, TEXT(\"Medium Acid\"));\n}\nelse\n{\n    UE_LOG(LogCategory, Log, TEXT(\"High Acid\"));\n}\n"
      })
    }), "\n", (0,jsx_runtime.jsx)(_components.h3, {
      id: "tabs-and-indenting",
      children: "Tabs and Indenting"
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "Below are some standards for indenting your code."
    }), "\n", (0,jsx_runtime.jsxs)(_components.ul, {
      children: ["\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsx)(_components.p, {
          children: "Indent code by execution block."
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsx)(_components.p, {
          children: "Use tabs for whitespace at the beginning of a line, not spaces. Set your tab size to 4 characters. Note, spaces are sometimes necessary and allowed for keeping code aligned regardless of the number of spaces in a tab. For example, when you are aligning code that follows non-tab characters."
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsx)(_components.p, {
          children: "If you are writing code in C#, please also use tabs, not spaces. The reason for this is that programmers often switch between C# and C++, and most prefer to use a consistent setting for tabs. Visual Studio defaults to using spaces for C# files, so you need to remember to change this setting when working on Unreal Engine code."
        }), "\n"]
      }), "\n"]
    }), "\n", (0,jsx_runtime.jsx)(_components.h3, {
      id: "switch-statements",
      children: "Switch Statements"
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "Except for empty cases (multiple cases having identical code), switch case statements should explicitly label that a case falls through to the next case. Either include a break, or include a \"falls through\" comment in each case. Other code control-transfer commands (return, continue, and so on) are fine as well."
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "Always have a default case. Include a break just in case someone adds a new case after the default."
    }), "\n", (0,jsx_runtime.jsx)(_components.pre, {
      children: (0,jsx_runtime.jsx)(_components.code, {
        className: "language-cpp",
        children: "switch (condition)\n{\n    case 1:\n        ...\n        // falls through\n\n    case 2:\n        ...\n        break;\n\n    case 3:\n        ...\n        return;\n\n    case 4:\n    case 5:\n        ...\n        break;\n\n    default:\n        break;\n}\n"
      })
    }), "\n", (0,jsx_runtime.jsx)(_components.h2, {
      id: "namespaces",
      children: "Namespaces"
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "You can use namespaces to organize your classes, functions and variables where appropriate. If you do use them, follow the rules below."
    }), "\n", (0,jsx_runtime.jsxs)(_components.ul, {
      children: ["\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsx)(_components.p, {
          children: "Most UE code is currently not wrapped in a global namespace."
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsx)(_components.p, {
          children: "Be careful to avoid collisions in the global scope, especially when using or including third party code."
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsx)(_components.p, {
          children: "Namespaces are not supported by UnrealHeaderTool."
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsxs)(_components.p, {
          children: ["Namespaces should not be used when defining ", (0,jsx_runtime.jsx)(_components.code, {
            children: "UCLASSes"
          }), ", ", (0,jsx_runtime.jsx)(_components.code, {
            children: "USTRUCTs"
          }), " and so on."]
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsxs)(_components.p, {
          children: ["New APIs which aren't ", (0,jsx_runtime.jsx)(_components.code, {
            children: "UCLASSes"
          }), ", ", (0,jsx_runtime.jsx)(_components.code, {
            children: "USTRUCTs"
          }), " etc, should be placed in a ", (0,jsx_runtime.jsx)(_components.code, {
            children: "UE::"
          }), " namespace, and ideally a nested namespace, e.g. ", (0,jsx_runtime.jsx)(_components.code, {
            children: "UE::Audio::"
          }), "."]
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsxs)(_components.p, {
          children: ["Namespaces which are used to hold implementation details which are not part of the public-facing API should go in a ", (0,jsx_runtime.jsx)(_components.code, {
            children: "Private"
          }), " namespace, e.g. ", (0,jsx_runtime.jsx)(_components.code, {
            children: "UE::Audio::Private::"
          }), "."]
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsxs)(_components.p, {
          children: [(0,jsx_runtime.jsx)(_components.code, {
            children: "Using"
          }), " declarations:"]
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsxs)(_components.p, {
          children: ["Do not put ", (0,jsx_runtime.jsx)(_components.code, {
            children: "using"
          }), " declarations in the global scope, even in a ", (0,jsx_runtime.jsx)(_components.code, {
            children: ".cpp"
          }), " file (it will cause problems with our \"unity\" build system.)"]
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsxs)(_components.p, {
          children: ["It's okay to put ", (0,jsx_runtime.jsx)(_components.code, {
            children: "using"
          }), " declarations within another namespace, or within a function body."]
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsxs)(_components.p, {
          children: ["If you put ", (0,jsx_runtime.jsx)(_components.code, {
            children: "using"
          }), " declarations within a namespace, this will carry over to other occurrences of that namespace in the same translation unit. As long as you are consistent, it will be fine."]
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsxs)(_components.p, {
          children: ["You can only use ", (0,jsx_runtime.jsx)(_components.code, {
            children: "using"
          }), " declarations in header files safely if you follow the above rules."]
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsx)(_components.p, {
          children: "Forward-declared types need to be declared within their respective namespace."
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsx)(_components.p, {
          children: "If you don't do this, you will get link errors."
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsx)(_components.p, {
          children: "If you declare a lot of classes or types within a namespace, it can be difficult to use those types in other global-scoped classes (for example, function signatures will need to use explicit namespace when appearing in class declarations)."
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsxs)(_components.p, {
          children: ["You can use ", (0,jsx_runtime.jsx)(_components.code, {
            children: "using"
          }), " declarations to only alias specific variables within a namespace into your scope."]
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsxs)(_components.p, {
          children: ["For example, using ", (0,jsx_runtime.jsx)(_components.code, {
            children: "Foo::FBar"
          }), ". However, we don't usually do that in Unreal code."]
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsx)(_components.p, {
          children: "Macros cannot live in a namespace."
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsxs)(_components.p, {
          children: ["They should be prefixed with ", (0,jsx_runtime.jsx)(_components.code, {
            children: "UE_"
          }), " instead of living in a namespace, for example ", (0,jsx_runtime.jsx)(_components.code, {
            children: "UE_LOG"
          }), "."]
        }), "\n"]
      }), "\n"]
    }), "\n", (0,jsx_runtime.jsx)(_components.h2, {
      id: "physical-dependencies",
      children: "Physical Dependencies"
    }), "\n", (0,jsx_runtime.jsxs)(_components.ul, {
      children: ["\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsx)(_components.p, {
          children: "File names should not be prefixed where possible."
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsxs)(_components.p, {
          children: ["For example, ", (0,jsx_runtime.jsx)(_components.code, {
            children: "Scene.cpp"
          }), " instead of ", (0,jsx_runtime.jsx)(_components.code, {
            children: "UScene.cpp"
          }), ". This makes it easy to use tools like Workspace Whiz or Visual Assist's Open File in Solution, by reducing the number of letters needed to identify the file you want."]
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsxs)(_components.p, {
          children: ["All headers should protect against multiple includes with the ", (0,jsx_runtime.jsx)(_components.code, {
            children: "#pragma once"
          }), " directive."]
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsxs)(_components.p, {
          children: ["Note that all compilers we use support ", (0,jsx_runtime.jsx)(_components.code, {
            children: "#pragma once"
          }), "."]
        }), "\n"]
      }), "\n"]
    }), "\n", (0,jsx_runtime.jsx)(_components.pre, {
      children: (0,jsx_runtime.jsx)(_components.code, {
        className: "language-cpp",
        children: "  #pragma once\n  //<file contents>\n"
      })
    }), "\n", (0,jsx_runtime.jsxs)(_components.ul, {
      children: ["\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsx)(_components.p, {
          children: "Try to minimize physical coupling."
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsx)(_components.p, {
          children: "In particular, avoid including standard library headers from other headers."
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsx)(_components.p, {
          children: "Forward declarations are preferred to including headers."
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsx)(_components.p, {
          children: "When including a header, be as fine grained as possible."
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsxs)(_components.p, {
          children: ["For example, do not include ", (0,jsx_runtime.jsx)(_components.code, {
            children: "Core.h"
          }), ". Instead, you should include the specific headers in Core that you need definitions from."]
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsx)(_components.p, {
          children: "Try to include every header you need directly to make fine-grained inclusion easier."
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsx)(_components.p, {
          children: "Don't rely on a header that is included indirectly by another header you include."
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsx)(_components.p, {
          children: "Don't rely on anything being included through another header. Include everything you need."
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsx)(_components.p, {
          children: "Modules have Private and Public source directories."
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsx)(_components.p, {
          children: "Any definitions that are needed by other modules must be in headers in the Public directory. Everything else should be in the Private directory. In older Unreal modules, these directories may still be called \"Src\" and \"Inc\", but those directories are meant to separate private and public code in the same way, and are not meant to separate header files from source files."
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsx)(_components.p, {
          children: "Don't worry about setting up your headers for precompiled header generation."
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsx)(_components.p, {
          children: "UnrealBuildTool can do a better job of this than you can."
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsx)(_components.p, {
          children: "Split large functions into logical sub-functions."
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsx)(_components.p, {
          children: "One area of compilers' optimizations is the elimination of common subexpressions. The larger your functions are, the more work the compiler has to do to identify them. This leads to greatly inflated build times."
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsx)(_components.p, {
          children: "Don't use a large number of inline functions."
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsx)(_components.p, {
          children: "Inline functions force rebuilds even in files which don't use them. Inline functions should only be used for trivial accessors and when profiling shows there is a benefit to doing so."
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsxs)(_components.p, {
          children: ["Be conservative in your use of ", (0,jsx_runtime.jsx)(_components.code, {
            children: "FORCEINLINE"
          }), "."]
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsx)(_components.p, {
          children: "All code and local variables will be expanded out into the calling function. This will cause the same build time problems as those caused by large functions."
        }), "\n"]
      }), "\n"]
    }), "\n", (0,jsx_runtime.jsx)(_components.h2, {
      id: "encapsulation",
      children: "Encapsulation"
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "Enforce encapsulation with the protection keywords. Class members should almost always be declared private unless they are part of the public/protected interface to the class. Use your best judgment, but always be aware that a lack of accessors makes it hard to refactor later without breaking plugins and existing projects."
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "If particular fields are only intended to be usable by derived classes, make them private and provide protected accessors."
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "Use final if your class is not designed to be derived from."
    }), "\n", (0,jsx_runtime.jsx)(_components.h2, {
      id: "general-style-issues",
      children: "General Style Issues"
    }), "\n", (0,jsx_runtime.jsxs)(_components.ul, {
      children: ["\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsx)(_components.p, {
          children: "Minimize dependency distance."
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsx)(_components.p, {
          children: "When code depends on a variable having a certain value, try to set that variable's value right before using it. Initializing a variable at the top of an execution block, and not using it for a hundred lines of code, gives lots of space for someone to accidentally change the value without realizing the dependency. Having it on the next line makes it clear why the variable is initialized the way it is and where it is used."
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsx)(_components.p, {
          children: "Split methods into sub-methods where possible."
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsx)(_components.p, {
          children: "It is easier for someone to look at a big picture, and then drill down to the interesting details, than it is to start with the details and reconstruct the big picture from them. In the same way, it is easier to understand a simple method, that calls a sequence of several well-named sub-methods, than it is to understand an equivalent method that simply contains all the code in those sub-methods."
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsx)(_components.p, {
          children: "In function declarations or function call sites, do not add a space between the function's name and the parentheses that precede the argument list."
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsx)(_components.p, {
          children: "Address compiler warnings."
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsxs)(_components.p, {
          children: ["Compiler warning messages mean something is wrong. Fix what the compiler is warning you about. If you absolutely can't address it, use ", (0,jsx_runtime.jsx)(_components.code, {
            children: "#pragma"
          }), " to suppress the warning, but this should only be done as a last resort."]
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsx)(_components.p, {
          children: "Leave a blank line at the end of the file."
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsxs)(_components.p, {
          children: ["All ", (0,jsx_runtime.jsx)(_components.code, {
            children: ".cpp"
          }), " and ", (0,jsx_runtime.jsx)(_components.code, {
            children: ".h"
          }), " files should include a blank line, to coordinate with gcc."]
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsx)(_components.p, {
          children: "Debug code should either be useful and polished, or not checked in."
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsx)(_components.p, {
          children: "Debug code that is intermixed with other code makes the other code harder to read."
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsxs)(_components.p, {
          children: ["Always use the ", (0,jsx_runtime.jsx)(_components.code, {
            children: "TEXT()"
          }), " macro around string literals."]
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsxs)(_components.p, {
          children: ["Without the ", (0,jsx_runtime.jsx)(_components.code, {
            children: "TEXT()"
          }), " macro, code that constructs ", (0,jsx_runtime.jsx)(_components.code, {
            children: "FStrings"
          }), " from literals will cause an undesirable string conversion process."]
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsx)(_components.p, {
          children: "Avoid repeating the same operation redundantly in loops."
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsxs)(_components.p, {
          children: ["Move common subexpressions out of loops to avoid redundant calculations. Make use of statics in some cases, to avoid globally-redundant operations across function calls, such as constructing an ", (0,jsx_runtime.jsx)(_components.code, {
            children: "FName"
          }), " from a string literal."]
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsx)(_components.p, {
          children: "Be mindful of hot reload."
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsx)(_components.p, {
          children: "Minimize dependencies to cut down on iteration time. Don't use inlining or templates for functions which are likely to change over a reload. Only use statics for things which are expected to remain constant over a reload."
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsx)(_components.p, {
          children: "Use intermediate variables to simplify complicated expressions."
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsx)(_components.p, {
          children: "If you have a complicated expression, it can be easier to understand if you split it into sub-expressions, that are assigned to intermediate variables, with names describing the meaning of the sub-expression within the parent expression. For example:"
        }), "\n"]
      }), "\n"]
    }), "\n", (0,jsx_runtime.jsx)(_components.pre, {
      children: (0,jsx_runtime.jsx)(_components.code, {
        className: "language-cpp",
        children: "  if ((Blah->BlahP->WindowExists->Etc && Stuff) &&\n      !(bPlayerExists && bGameStarted && bPlayerStillHasPawn &&\n      IsTuesday())))\n  {\n      DoSomething();\n  }\n"
      })
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "Should be replaced with:"
    }), "\n", (0,jsx_runtime.jsx)(_components.pre, {
      children: (0,jsx_runtime.jsx)(_components.code, {
        className: "language-cpp",
        children: "const bool bIsLegalWindow = Blah->BlahP->WindowExists->Etc && Stuff;\nconst bool bIsPlayerDead = bPlayerExists && bGameStarted && bPlayerStillHasPawn && IsTuesday();\nif (bIsLegalWindow && !bIsPlayerDead)\n{\n    DoSomething();\n}\n"
      })
    }), "\n", (0,jsx_runtime.jsxs)(_components.ul, {
      children: ["\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsx)(_components.p, {
          children: "Pointers and references should only have one space to the right of the pointer or reference."
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsxs)(_components.p, {
          children: ["This makes it easy to quickly use ", (0,jsx_runtime.jsx)(_components.strong, {
            children: "Find in Files"
          }), " for all pointers or references to a certain type. For example:"]
        }), "\n"]
      }), "\n"]
    }), "\n", (0,jsx_runtime.jsx)(_components.pre, {
      children: (0,jsx_runtime.jsx)(_components.code, {
        className: "language-cpp",
        children: "  // Use this\n  FShaderType* Ptr\n\n  // Do not use these:\n  FShaderType *Ptr\n  FShaderType * Ptr\n"
      })
    }), "\n", (0,jsx_runtime.jsxs)(_components.ul, {
      children: ["\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsx)(_components.p, {
          children: "Shadowed variables are not allowed."
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsxs)(_components.p, {
          children: ["C++ allows variables to be shadowed from an outer scope, but this makes usage ambiguous to a reader. For example, there are three usable ", (0,jsx_runtime.jsx)(_components.code, {
            children: "Count"
          }), " variables in this member function:"]
        }), "\n"]
      }), "\n"]
    }), "\n", (0,jsx_runtime.jsx)(_components.pre, {
      children: (0,jsx_runtime.jsx)(_components.code, {
        className: "language-cpp",
        children: "  class FSomeClass\n  {\n  public:\n      void Func(const int32 Count)\n      {\n          for (int32 Count = 0; Count != 10; ++Count)\n          {\n              // Use Count\n          }\n      }\n\n  private:\n      int32 Count;\n  }\n"
      })
    }), "\n", (0,jsx_runtime.jsxs)(_components.ul, {
      children: ["\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsx)(_components.p, {
          children: "Avoid using anonymous literals in function calls."
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsx)(_components.p, {
          children: "Prefer named constants which describe their meaning. This makes intent more obvious to a casual reader as it avoids the need to look up the function declaration to understand it."
        }), "\n"]
      }), "\n"]
    }), "\n", (0,jsx_runtime.jsx)(_components.pre, {
      children: (0,jsx_runtime.jsx)(_components.code, {
        className: "language-cpp",
        children: "  // Old style\n  Trigger(TEXT(\"Soldier\"), 5, true);.\n\n  // New style\n  const FName ObjectName                = TEXT(\"Soldier\");\n  const float CooldownInSeconds         = 5;\n  const bool bVulnerableDuringCooldown  = true;\n  Trigger(ObjectName, CooldownInSeconds, bVulnerableDuringCooldown);\n"
      })
    }), "\n", (0,jsx_runtime.jsxs)(_components.ul, {
      children: ["\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsx)(_components.p, {
          children: "Avoid defining non-trivial static variables in headers."
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsx)(_components.p, {
          children: "Non-trivial static variables cause an instance to be compiled into in every translation unit that includes that header:"
        }), "\n"]
      }), "\n"]
    }), "\n", (0,jsx_runtime.jsx)(_components.pre, {
      children: (0,jsx_runtime.jsx)(_components.code, {
        className: "language-cpp",
        children: "  // SomeModule.h\n  static const FString GUsefulNamedString = TEXT(\"String\");\n\n  // *Replace the above with:*\n\n  // SomeModule.h\n  extern SOMEMODULE_API const FString GUsefulNamedString;\n\n  // SomeModule.cpp\n  const FString GUsefulNamedString = TEXT(\"String\");\n"
      })
    }), "\n", (0,jsx_runtime.jsxs)(_components.ul, {
      children: ["\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsx)(_components.p, {
          children: "Avoid making extensive changes which do not change the code's behavior (for example: changing whitespace or mass renaming of private variables) as these cause unnecessary noise in source history and are disruptive when merging."
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsx)(_components.p, {
          children: "If such a change is important, for example fixing broken indentation caused by an automated merge tool, it should be submitted on its own and not mixed with behavioral changes."
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsx)(_components.p, {
          children: "Prefer to fix whitespace or other minor coding standard violations only when other edits are being made to the same lines or nearby code."
        }), "\n"]
      }), "\n"]
    }), "\n", (0,jsx_runtime.jsx)(_components.h2, {
      id: "api-design-guidelines",
      children: "API Design Guidelines"
    }), "\n", (0,jsx_runtime.jsxs)(_components.ul, {
      children: ["\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsx)(_components.p, {
          children: "Boolean function parameters should be avoided."
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsxs)(_components.p, {
          children: ["In particular, boolean parameters should be avoided for flags passed to functions. These have the same anonymous literal problem as mentioned previously, but they also tend to multiply over time as APIs get extended with more behavior. Instead, prefer an enum (see the advice on use of enums as flags in the ", (0,jsx_runtime.jsx)(_components.a, {
            href: "https://dev.epicgames.com/documentation/en-us/unreal-engine/epic-cplusplus-coding-standard-for-unreal-engine#strongly-typedenums",
            children: "Strongly-Typed Enums"
          }), " section):"]
        }), "\n"]
      }), "\n"]
    }), "\n", (0,jsx_runtime.jsx)(_components.pre, {
      children: (0,jsx_runtime.jsx)(_components.code, {
        className: "language-cpp",
        children: "  // Old style\n  FCup* MakeCupOfTea(FTea* Tea, bool bAddSugar = false, bool bAddMilk = false, bool bAddHoney = false, bool bAddLemon = false);\n  FCup* Cup = MakeCupOfTea(Tea, false, true, true);\n\n  // New style\n  enum class ETeaFlags\n  {\n      None,\n      Milk  = 0x01,\n      Sugar = 0x02,\n      Honey = 0x04,\n      Lemon = 0x08\n  };\n  ENUM_CLASS_FLAGS(ETeaFlags)\n\n  FCup* MakeCupOfTea(FTea* Tea, ETeaFlags Flags = ETeaFlags::None);\n  FCup* Cup = MakeCupOfTea(Tea, ETeaFlags::Milk | ETeaFlags::Honey);\n"
      })
    }), "\n", (0,jsx_runtime.jsxs)(_components.ul, {
      children: ["\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsx)(_components.p, {
          children: "This form prevents the accidental transposing of flags, avoids accidental conversion from pointer and integer arguments, removes the need to repeat redundant defaults, and is more efficient."
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsxs)(_components.p, {
          children: ["It is acceptable to use ", (0,jsx_runtime.jsx)(_components.code, {
            children: "bools"
          }), " as arguments when they are the complete state to be passed to a function like a setter, such as ", (0,jsx_runtime.jsx)(_components.code, {
            children: "void FWidget::SetEnabled(bool bEnabled)"
          }), ". Though consider refactoring if this changes."]
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsx)(_components.p, {
          children: "Avoid overly-long function parameter lists."
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsx)(_components.p, {
          children: "If a function takes many parameters then consider passing a dedicated struct instead:"
        }), "\n"]
      }), "\n"]
    }), "\n", (0,jsx_runtime.jsx)(_components.pre, {
      children: (0,jsx_runtime.jsx)(_components.code, {
        className: "language-cpp",
        children: "  // Old style\n  TUniquePtr<FCup[]> MakeTeaForParty(const FTeaFlags* TeaPreferences, uint32 NumCupsToMake, FKettle* Kettle, ETeaType TeaType = ETeaType::EnglishBreakfast, float BrewingTimeInSeconds = 120.0f);\n\n  // New style\n  struct FTeaPartyParams\n  {\n      const FTeaFlags* TeaPreferences       = nullptr;\n      uint32           NumCupsToMake        = 0;\n      FKettle*         Kettle               = nullptr;\n      ETeaType         TeaType              = ETeaType::EnglishBreakfast;\n      float            BrewingTimeInSeconds = 120.0f;\n  };\n  TUniquePtr<FCup[]> MakeTeaForParty(const FTeaPartyParams& Params);\n"
      })
    }), "\n", (0,jsx_runtime.jsxs)(_components.ul, {
      children: ["\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsxs)(_components.p, {
          children: ["Avoid overloading functions by ", (0,jsx_runtime.jsx)(_components.code, {
            children: "bool"
          }), " and ", (0,jsx_runtime.jsx)(_components.code, {
            children: "FString"
          }), "."]
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsx)(_components.p, {
          children: "This can have unexpected behavior:"
        }), "\n"]
      }), "\n"]
    }), "\n", (0,jsx_runtime.jsx)(_components.pre, {
      children: (0,jsx_runtime.jsx)(_components.code, {
        className: "language-cpp",
        children: "  void Func(const FString& String);\n  void Func(bool bBool);\n\n  Func(TEXT(\"String\")); // Calls the bool overload!\n"
      })
    }), "\n", (0,jsx_runtime.jsxs)(_components.ul, {
      children: ["\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsx)(_components.p, {
          children: "Interface classes should always be abstract."
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsx)(_components.p, {
          children: "Interface classes are prefixed with \"I\" and must not have member variables. Interfaces are allowed to contain methods that are not pure-virtual, and can contain methods that are non-virtual or static, as long as they are implemented inline."
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["\n", (0,jsx_runtime.jsxs)(_components.p, {
          children: ["Use the ", (0,jsx_runtime.jsx)(_components.code, {
            children: "virtual"
          }), " and ", (0,jsx_runtime.jsx)(_components.code, {
            children: "override"
          }), " keywords when declaring an overriding method."]
        }), "\n"]
      }), "\n"]
    }), "\n", (0,jsx_runtime.jsxs)(_components.p, {
      children: ["When declaring a virtual function in a derived class that overrides a virtual function in the parent class, you must use both the ", (0,jsx_runtime.jsx)(_components.code, {
        children: "virtual"
      }), " and the ", (0,jsx_runtime.jsx)(_components.code, {
        children: "override"
      }), " keywords. For example:"]
    }), "\n", (0,jsx_runtime.jsx)(_components.pre, {
      children: (0,jsx_runtime.jsx)(_components.code, {
        className: "language-cpp",
        children: "class A\n{\npublic:\n    virtual void F() {}\n};\n\nclass B : public A\n{\npublic:\n    virtual void F() override;\n}\n"
      })
    }), "\n", (0,jsx_runtime.jsxs)(_components.p, {
      children: ["There is a lot of existing code that doesn't follow this yet, due to the recent addition of the ", (0,jsx_runtime.jsx)(_components.code, {
        children: "override"
      }), " keyword. The ", (0,jsx_runtime.jsx)(_components.code, {
        children: "override"
      }), " keyword should be added to that code when convenient."]
    }), "\n", (0,jsx_runtime.jsxs)(_components.ul, {
      children: ["\n", (0,jsx_runtime.jsx)(_components.li, {
        children: "UObjects should be passed around by pointer, not reference. If null is not expected by a function, this should be documented by the API or handled appropriately. For example:"
      }), "\n"]
    }), "\n", (0,jsx_runtime.jsx)(_components.pre, {
      children: (0,jsx_runtime.jsx)(_components.code, {
        className: "language-cpp",
        children: "      // Bad\n      void AddActorToList(AActor& Obj);\n\n      // Good\n      void AddActorToList(AActor* Obj);\n"
      })
    }), "\n", (0,jsx_runtime.jsx)(_components.h2, {
      id: "platform-specific-code",
      children: "Platform-Specific Code"
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "Platform-specific code should always be abstracted and implemented in platform-specific source files in appropriately named subdirectories, for example:"
    }), "\n", (0,jsx_runtime.jsx)(_components.pre, {
      children: (0,jsx_runtime.jsx)(_components.code, {
        className: "language-cpp",
        children: "Engine/Platforms/[PLATFORM]/Source/Runtime/Core/Private/[PLATFORM]PlatformMemory.cpp\n"
      })
    }), "\n", (0,jsx_runtime.jsxs)(_components.p, {
      children: ["In general, you should avoid adding any uses of ", (0,jsx_runtime.jsx)(_components.code, {
        children: "PLATFORM_[PLATFORM]"
      }), ". For example, avoid adding ", (0,jsx_runtime.jsx)(_components.code, {
        children: "PLATFORM_XBOXONE"
      }), " to code outside of a directory named ", (0,jsx_runtime.jsx)(_components.code, {
        children: "[PLATFORM]"
      }), ". Instead, extend the hardware abstraction layer to add a static function, for example in FPlatformMisc:"]
    }), "\n", (0,jsx_runtime.jsx)(_components.pre, {
      children: (0,jsx_runtime.jsx)(_components.code, {
        className: "language-cpp",
        children: "FORCEINLINE static int32 GetMaxPathLength()\n{\n    return 128;\n}\n"
      })
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "Platforms can then override this function, returning either a platform-specific constant value or even using platform APIs to determine the result. If you force-inline the function it has the same performance characteristics as using a define."
    }), "\n", (0,jsx_runtime.jsxs)(_components.p, {
      children: ["In cases where a define is absolutely necessary, create new ", (0,jsx_runtime.jsx)(_components.code, {
        children: "#define"
      }), " directives that describe particular properties that can apply to a platform, for example ", (0,jsx_runtime.jsx)(_components.code, {
        children: "PLATFORM_USE_PTHREADS"
      }), ". Set the default value in ", (0,jsx_runtime.jsx)(_components.code, {
        children: "Platform.h"
      }), " and override for any platforms which require it in the platform-specific ", (0,jsx_runtime.jsx)(_components.code, {
        children: "Platform.h"
      }), " file."]
    }), "\n", (0,jsx_runtime.jsxs)(_components.p, {
      children: ["For example, in ", (0,jsx_runtime.jsx)(_components.code, {
        children: "Platform.h"
      }), " we have:"]
    }), "\n", (0,jsx_runtime.jsx)(_components.pre, {
      children: (0,jsx_runtime.jsx)(_components.code, {
        className: "language-cpp",
        children: "#ifndef PLATFORM_USE_PTHREADS\n    #define PLATFORM_USE_PTHREADS 1\n#endif\n"
      })
    }), "\n", (0,jsx_runtime.jsxs)(_components.p, {
      children: [(0,jsx_runtime.jsx)(_components.code, {
        children: "WindowsPlatform.h"
      }), " has:"]
    }), "\n", (0,jsx_runtime.jsx)(_components.pre, {
      children: (0,jsx_runtime.jsx)(_components.code, {
        className: "language-cpp",
        children: "#define PLATFORM_USE_PTHREADS 0\n"
      })
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "Cross-platform code can then use the define directly without needing to know the platform."
    }), "\n", (0,jsx_runtime.jsx)(_components.pre, {
      children: (0,jsx_runtime.jsx)(_components.code, {
        className: "language-cpp",
        children: "#if PLATFORM_USE_PTHREADS\n    #include \"HAL/PThreadRunnableThread.h\"\n#endif\n"
      })
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "We centralize the platform-specific details of the engine which allows details to be contained entirely within platform-specific source files. Doing so makes it easier to maintain the engine across multiple platforms, additionally you are able to port code to new platforms without the need to scour the codebase for platform-specific defines."
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "Keeping platform code in platform-specific folders is also a requirement for NDA platforms such as PlayStation, Xbox and Nintendo Switch."
    }), "\n", (0,jsx_runtime.jsxs)(_components.p, {
      children: ["It is important to ensure the code compiles and runs regardless of whether the ", (0,jsx_runtime.jsx)(_components.code, {
        children: "[PLATFORM]"
      }), " subdirectory is present. In other words, cross-platform code should never be dependent on platform-specific code."]
    })]
  });
}
function MDXContent(props = {}) {
  const {wrapper: MDXLayout} = {
    ...(0,lib/* useMDXComponents */.R)(),
    ...props.components
  };
  return MDXLayout ? (0,jsx_runtime.jsx)(MDXLayout, {
    ...props,
    children: (0,jsx_runtime.jsx)(_createMdxContent, {
      ...props
    })
  }) : _createMdxContent(props);
}



/***/ }

}]);