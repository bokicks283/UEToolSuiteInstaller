"use strict";
(globalThis["webpackChunkue_project_docs"] = globalThis["webpackChunkue_project_docs"] || []).push([[4015],{

/***/ 7761
(__unused_webpack_module, __webpack_exports__, __webpack_require__) {

// ESM COMPAT FLAG
__webpack_require__.r(__webpack_exports__);

// EXPORTS
__webpack_require__.d(__webpack_exports__, {
  assets: () => (/* binding */ assets),
  contentTitle: () => (/* binding */ contentTitle),
  "default": () => (/* binding */ MDXContent),
  frontMatter: () => (/* binding */ frontMatter),
  metadata: () => (/* reexport */ site_docs_project_docs_readme_md_90e_namespaceObject),
  toc: () => (/* binding */ toc)
});

;// ./.docusaurus/docusaurus-plugin-content-docs/default/site-docs-project-docs-readme-md-90e.json
const site_docs_project_docs_readme_md_90e_namespaceObject = /*#__PURE__*/JSON.parse('{"id":"ProjectDocs/README","title":"Project Docs","description":"Use this domain for game-specific and project-specific documentation that should not live inside the shared standards domain.","source":"@site/../Docs/ProjectDocs/README.md","sourceDirName":"ProjectDocs","slug":"/project-docs","permalink":"/docs/project-docs","draft":false,"unlisted":false,"tags":[],"version":"current","sidebarPosition":1,"frontMatter":{"title":"Project Docs","sidebar_position":1,"slug":"/project-docs"},"sidebar":"project-docs-sidebar"}');
// EXTERNAL MODULE: ./node_modules/react/jsx-runtime.js
var jsx_runtime = __webpack_require__(4848);
// EXTERNAL MODULE: ./node_modules/@mdx-js/react/lib/index.js
var lib = __webpack_require__(8453);
// EXTERNAL MODULE: ./node_modules/@docusaurus/theme-classic/lib/theme/DocCardList/index.js + 4 modules
var DocCardList = __webpack_require__(3021);
;// ../Docs/ProjectDocs/README.md


const frontMatter = {
	title: 'Project Docs',
	sidebar_position: 1,
	slug: '/project-docs'
};
const contentTitle = 'Project Docs';

const assets = {

};




const toc = [{
  "value": "Good Fits",
  "id": "good-fits",
  "level": 2
}, {
  "value": "Suggested Starting Structure",
  "id": "suggested-starting-structure",
  "level": 2
}, {
  "value": "Browse This Domain",
  "id": "browse-this-domain",
  "level": 2
}];
function _createMdxContent(props) {
  const _components = {
    h1: "h1",
    h2: "h2",
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
        id: "project-docs",
        children: "Project Docs"
      })
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "Use this domain for game-specific and project-specific documentation that should not live inside the shared standards domain."
    }), "\n", (0,jsx_runtime.jsx)(_components.h2, {
      id: "good-fits",
      children: "Good Fits"
    }), "\n", (0,jsx_runtime.jsxs)(_components.ul, {
      children: ["\n", (0,jsx_runtime.jsx)(_components.li, {
        children: "feature specs"
      }), "\n", (0,jsx_runtime.jsx)(_components.li, {
        children: "system overviews"
      }), "\n", (0,jsx_runtime.jsx)(_components.li, {
        children: "production notes"
      }), "\n", (0,jsx_runtime.jsx)(_components.li, {
        children: "milestone plans"
      }), "\n", (0,jsx_runtime.jsx)(_components.li, {
        children: "gameplay rules"
      }), "\n", (0,jsx_runtime.jsx)(_components.li, {
        children: "content pipelines unique to the project"
      }), "\n", (0,jsx_runtime.jsx)(_components.li, {
        children: "team runbooks tied to the current game"
      }), "\n"]
    }), "\n", (0,jsx_runtime.jsx)(_components.h2, {
      id: "suggested-starting-structure",
      children: "Suggested Starting Structure"
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "Create sections for the areas your team actually uses. Good starting categories are:"
    }), "\n", (0,jsx_runtime.jsxs)(_components.ul, {
      children: ["\n", (0,jsx_runtime.jsx)(_components.li, {
        children: "Design"
      }), "\n", (0,jsx_runtime.jsx)(_components.li, {
        children: "Gameplay"
      }), "\n", (0,jsx_runtime.jsx)(_components.li, {
        children: "World"
      }), "\n", (0,jsx_runtime.jsx)(_components.li, {
        children: "UI"
      }), "\n", (0,jsx_runtime.jsx)(_components.li, {
        children: "Audio"
      }), "\n", (0,jsx_runtime.jsx)(_components.li, {
        children: "Production"
      }), "\n", (0,jsx_runtime.jsx)(_components.li, {
        children: "Release"
      }), "\n"]
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "Keep this domain lean at first. Add structure only when the project needs it."
    }), "\n", (0,jsx_runtime.jsx)(_components.h2, {
      id: "browse-this-domain",
      children: "Browse This Domain"
    }), "\n", (0,jsx_runtime.jsx)(DocCardList/* default */.A, {})]
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



/***/ },

/***/ 3021
(__unused_webpack_module, __webpack_exports__, __webpack_require__) {


// EXPORTS
__webpack_require__.d(__webpack_exports__, {
  A: () => (/* binding */ DocCardList)
});

// EXTERNAL MODULE: ./node_modules/react/index.js
var react = __webpack_require__(6540);
// EXTERNAL MODULE: ./node_modules/clsx/dist/clsx.mjs
var clsx = __webpack_require__(4164);
// EXTERNAL MODULE: ./node_modules/@docusaurus/plugin-content-docs/lib/client/docsUtils.js + 1 modules
var docsUtils = __webpack_require__(4718);
// EXTERNAL MODULE: ./node_modules/@docusaurus/core/lib/client/exports/Link.js
var Link = __webpack_require__(8774);
// EXTERNAL MODULE: ./node_modules/@docusaurus/core/lib/client/exports/useDocusaurusContext.js
var useDocusaurusContext = __webpack_require__(4586);
;// ./node_modules/@docusaurus/theme-common/lib/utils/usePluralForm.js
/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */// We want to ensurer a stable plural form order in all cases
// It is more convenient and natural to handle "small values" first
// See https://x.com/sebastienlorber/status/1366820663261077510
const OrderedPluralForms=['zero','one','two','few','many','other'];function sortPluralForms(pluralForms){return OrderedPluralForms.filter(pf=>pluralForms.includes(pf));}// Hardcoded english/fallback implementation
const EnglishPluralForms={locale:'en',pluralForms:sortPluralForms(['one','other']),select:count=>count===1?'one':'other'};function createLocalePluralForms(locale){const pluralRules=new Intl.PluralRules(locale);return{locale,pluralForms:sortPluralForms(pluralRules.resolvedOptions().pluralCategories),select:count=>pluralRules.select(count)};}/**
 * Poor man's `PluralSelector` implementation, using an English fallback. We
 * want a lightweight, future-proof and good-enough solution. We don't want a
 * perfect and heavy solution.
 *
 * Docusaurus classic theme has only 2 deeply nested labels requiring complex
 * plural rules. We don't want to use `Intl` + `PluralRules` polyfills + full
 * ICU syntax (react-intl) just for that.
 *
 * Notes:
 * - 2021: 92+% Browsers support `Intl.PluralRules`, and support will increase
 * in the future
 * - NodeJS >= 13 has full ICU support by default
 * - In case of "mismatch" between SSR and Browser ICU support, React keeps
 * working!
 */function useLocalePluralForms(){const{i18n:{currentLocale}}=(0,useDocusaurusContext/* default */.A)();return (0,react.useMemo)(()=>{try{return createLocalePluralForms(currentLocale);}catch(err){console.error(`Failed to use Intl.PluralRules for locale "${currentLocale}".
Docusaurus will fallback to the default (English) implementation.
Error: ${err.message}
`);return EnglishPluralForms;}},[currentLocale]);}function selectPluralMessage(pluralMessages,count,localePluralForms){const separator='|';const parts=pluralMessages.split(separator);if(parts.length===1){return parts[0];}if(parts.length>localePluralForms.pluralForms.length){console.error(`For locale=${localePluralForms.locale}, a maximum of ${localePluralForms.pluralForms.length} plural forms are expected (${localePluralForms.pluralForms.join(',')}), but the message contains ${parts.length}: ${pluralMessages}`);}const pluralForm=localePluralForms.select(count);const pluralFormIndex=localePluralForms.pluralForms.indexOf(pluralForm);// In case of not enough plural form messages, we take the last one (other)
// instead of returning undefined
return parts[Math.min(pluralFormIndex,parts.length-1)];}/**
 * Reads the current locale and returns an interface very similar to
 * `Intl.PluralRules`.
 */function usePluralForm(){const localePluralForm=useLocalePluralForms();return{selectMessage:(count,pluralMessages)=>selectPluralMessage(pluralMessages,count,localePluralForm)};}
// EXTERNAL MODULE: ./node_modules/@docusaurus/core/lib/client/exports/isInternalUrl.js
var isInternalUrl = __webpack_require__(6654);
// EXTERNAL MODULE: ./node_modules/@docusaurus/core/lib/client/exports/Translate.js + 1 modules
var Translate = __webpack_require__(1312);
// EXTERNAL MODULE: ./node_modules/@docusaurus/theme-classic/lib/theme/Heading/index.js + 1 modules
var Heading = __webpack_require__(1107);
;// ./node_modules/@docusaurus/theme-classic/lib/theme/DocCard/styles.module.css
// extracted by mini-css-extract-plugin
/* harmony default export */ const styles_module = ({"cardContainer":"cardContainer_fWXF","cardTitle":"cardTitle_rnsV","cardDescription":"cardDescription_PWke"});
// EXTERNAL MODULE: ./node_modules/react/jsx-runtime.js
var jsx_runtime = __webpack_require__(4848);
;// ./node_modules/@docusaurus/theme-classic/lib/theme/DocCard/index.js
/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */function useCategoryItemsPlural(){const{selectMessage}=usePluralForm();return count=>selectMessage(count,(0,Translate/* translate */.T)({message:'1 item|{count} items',id:'theme.docs.DocCard.categoryDescription.plurals',description:'The default description for a category card in the generated index about how many items this category includes'},{count}));}function CardContainer({className,href,children}){return/*#__PURE__*/(0,jsx_runtime.jsx)(Link/* default */.A,{href:href,className:(0,clsx/* default */.A)('card padding--lg',styles_module.cardContainer,className),children:children});}function CardLayout({className,href,icon,title,description}){return/*#__PURE__*/(0,jsx_runtime.jsxs)(CardContainer,{href:href,className:className,children:[/*#__PURE__*/(0,jsx_runtime.jsxs)(Heading/* default */.A,{as:"h2",className:(0,clsx/* default */.A)('text--truncate',styles_module.cardTitle),title:title,children:[icon," ",title]}),description&&/*#__PURE__*/(0,jsx_runtime.jsx)("p",{className:(0,clsx/* default */.A)('text--truncate',styles_module.cardDescription),title:description,children:description})]});}function CardCategory({item}){const href=(0,docsUtils/* findFirstSidebarItemLink */.Nr)(item);const categoryItemsPlural=useCategoryItemsPlural();// Unexpected: categories that don't have a link have been filtered upfront
if(!href){return null;}return/*#__PURE__*/(0,jsx_runtime.jsx)(CardLayout,{className:item.className,href:href,icon:"\uD83D\uDDC3\uFE0F",title:item.label,description:item.description??categoryItemsPlural(item.items.length)});}function CardLink({item}){const icon=(0,isInternalUrl/* default */.A)(item.href)?'📄️':'🔗';const doc=(0,docsUtils/* useDocById */.cC)(item.docId??undefined);return/*#__PURE__*/(0,jsx_runtime.jsx)(CardLayout,{className:item.className,href:item.href,icon:icon,title:item.label,description:item.description??doc?.description});}function DocCard({item}){switch(item.type){case'link':return/*#__PURE__*/(0,jsx_runtime.jsx)(CardLink,{item:item});case'category':return/*#__PURE__*/(0,jsx_runtime.jsx)(CardCategory,{item:item});default:throw new Error(`unknown item type ${JSON.stringify(item)}`);}}
;// ./node_modules/@docusaurus/theme-classic/lib/theme/DocCardList/styles.module.css
// extracted by mini-css-extract-plugin
/* harmony default export */ const DocCardList_styles_module = ({"docCardListItem":"docCardListItem_W1sv"});
;// ./node_modules/@docusaurus/theme-classic/lib/theme/DocCardList/index.js
/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */function DocCardListForCurrentSidebarCategory({className}){const items=(0,docsUtils/* useCurrentSidebarSiblings */.a4)();return/*#__PURE__*/(0,jsx_runtime.jsx)(DocCardList,{items:items,className:className});}function DocCardListItem({item}){return/*#__PURE__*/(0,jsx_runtime.jsx)("article",{className:(0,clsx/* default */.A)(DocCardList_styles_module.docCardListItem,'col col--6'),children:/*#__PURE__*/(0,jsx_runtime.jsx)(DocCard,{item:item})});}function DocCardList(props){const{items,className}=props;if(!items){return/*#__PURE__*/(0,jsx_runtime.jsx)(DocCardListForCurrentSidebarCategory,{...props});}const filteredItems=(0,docsUtils/* filterDocCardListItems */.d1)(items);return/*#__PURE__*/(0,jsx_runtime.jsx)("section",{className:(0,clsx/* default */.A)('row',className),children:filteredItems.map((item,index)=>/*#__PURE__*/(0,jsx_runtime.jsx)(DocCardListItem,{item:item},index))});}

/***/ }

}]);