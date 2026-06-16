"use strict";
(globalThis["webpackChunkue_project_docs"] = globalThis["webpackChunkue_project_docs"] || []).push([[5708],{

/***/ 1434
(__unused_webpack_module, __webpack_exports__, __webpack_require__) {

// ESM COMPAT FLAG
__webpack_require__.r(__webpack_exports__);

// EXPORTS
__webpack_require__.d(__webpack_exports__, {
  assets: () => (/* binding */ assets),
  contentTitle: () => (/* binding */ contentTitle),
  "default": () => (/* binding */ MDXContent),
  frontMatter: () => (/* binding */ frontMatter),
  metadata: () => (/* reexport */ site_docs_readme_md_074_namespaceObject),
  toc: () => (/* binding */ toc)
});

;// ./.docusaurus/docusaurus-plugin-content-docs/default/site-docs-readme-md-074.json
const site_docs_readme_md_074_namespaceObject = /*#__PURE__*/JSON.parse('{"id":"README","title":"Docs Home","description":"This site starts with two domains so standards and project-specific docs do not fight for the same sidebar.","source":"@site/../Docs/README.md","sourceDirName":".","slug":"/","permalink":"/docs/","draft":false,"unlisted":false,"tags":[],"version":"current","frontMatter":{"title":"Docs Home","slug":"/"}}');
// EXTERNAL MODULE: ./node_modules/react/jsx-runtime.js
var jsx_runtime = __webpack_require__(4848);
// EXTERNAL MODULE: ./node_modules/@mdx-js/react/lib/index.js
var lib = __webpack_require__(8453);
;// ../Docs/README.md


const frontMatter = {
	title: 'Docs Home',
	slug: '/'
};
const contentTitle = 'Docs Home';

const assets = {

};



const toc = [{
  "value": "Domains",
  "id": "domains",
  "level": 2
}, {
  "value": "Workflow &amp; Standards",
  "id": "workflow--standards",
  "level": 3
}, {
  "value": "Project Docs",
  "id": "project-docs",
  "level": 3
}, {
  "value": "Site Administration",
  "id": "site-administration",
  "level": 2
}, {
  "value": "Conventions",
  "id": "conventions",
  "level": 2
}];
function _createMdxContent(props) {
  const _components = {
    a: "a",
    code: "code",
    h1: "h1",
    h2: "h2",
    h3: "h3",
    header: "header",
    li: "li",
    p: "p",
    ul: "ul",
    ...(0,lib/* useMDXComponents */.R)(),
    ...props.components
  };
  return (0,jsx_runtime.jsxs)(jsx_runtime.Fragment, {
    children: [(0,jsx_runtime.jsx)(_components.header, {
      children: (0,jsx_runtime.jsx)(_components.h1, {
        id: "docs-home",
        children: "Docs Home"
      })
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "This site starts with two domains so standards and project-specific docs do not fight for the same sidebar."
    }), "\n", (0,jsx_runtime.jsx)(_components.h2, {
      id: "domains",
      children: "Domains"
    }), "\n", (0,jsx_runtime.jsx)(_components.h3, {
      id: "workflow--standards",
      children: "Workflow & Standards"
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "Shared setup, workflow, testing, coding standards, docs tooling, and AI context."
    }), "\n", (0,jsx_runtime.jsxs)(_components.ul, {
      children: ["\n", (0,jsx_runtime.jsx)(_components.li, {
        children: (0,jsx_runtime.jsx)(_components.a, {
          href: "/docs/workflow-standards",
          children: "Open Workflow & Standards"
        })
      }), "\n"]
    }), "\n", (0,jsx_runtime.jsx)(_components.h3, {
      id: "project-docs",
      children: "Project Docs"
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "Project-specific specs, design notes, system docs, production notes, and team runbooks."
    }), "\n", (0,jsx_runtime.jsxs)(_components.ul, {
      children: ["\n", (0,jsx_runtime.jsx)(_components.li, {
        children: (0,jsx_runtime.jsx)(_components.a, {
          href: "/docs/project-docs",
          children: "Open Project Docs"
        })
      }), "\n"]
    }), "\n", (0,jsx_runtime.jsx)(_components.h2, {
      id: "site-administration",
      children: "Site Administration"
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "Need to change theme, branding, overrides, or create a new domain?"
    }), "\n", (0,jsx_runtime.jsxs)(_components.ul, {
      children: ["\n", (0,jsx_runtime.jsx)(_components.li, {
        children: (0,jsx_runtime.jsx)(_components.a, {
          href: "/docs/?siteAdmin=1",
          children: "Open Site Settings"
        })
      }), "\n"]
    }), "\n", (0,jsx_runtime.jsx)(_components.h2, {
      id: "conventions",
      children: "Conventions"
    }), "\n", (0,jsx_runtime.jsxs)(_components.ul, {
      children: ["\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["Keep long-form content in ", (0,jsx_runtime.jsx)(_components.code, {
          children: "Docs/"
        }), "."]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["Keep Docusaurus shell and theme behavior in ", (0,jsx_runtime.jsx)(_components.code, {
          children: "website/"
        }), "."]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["Prefer ", (0,jsx_runtime.jsx)(_components.code, {
          children: "_category_.json"
        }), ", landing ", (0,jsx_runtime.jsx)(_components.code, {
          children: "README.md"
        }), " pages, and autogenerated sidebars over hand-maintained navigation."]
      }), "\n", (0,jsx_runtime.jsx)(_components.li, {
        children: "Update docs in the same branch as the behavior they describe."
      }), "\n"]
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