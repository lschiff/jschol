// ##### Sidebar Component ##### //

import React from 'react'

import RecentArticlesComp from "../components/RecentArticlesComp.jsx"
import ArbitraryHTMLComp from "../components/ArbitraryHTMLComp.jsx"
import SocialFeedComp from "../components/SocialFeedComp.jsx"

export default class SidebarComp extends React.Component {
  render = () =>
    <div>
      {this.props.data.map(sb =>
        sb.kind == "RecentArticles" && sb.attrs.items == 0 ? null
        :
        <section key={sb.id} className="o-columnbox1">
          <header>
            <h2>{(sb.attrs && sb.attrs.title) ? sb.attrs.title : sb.kind.replace(/([a-z])([A-Z][a-z])/g, "$1 $2")}</h2>
          </header>
          {   sb.kind == "Text"           ? <ArbitraryHTMLComp html={sb.attrs.html} h1Level={3}/>
            : sb.kind == "RecentArticles" ? <RecentArticlesComp data={sb.attrs}/>
            : sb.kind == "TwitterFeed" && sb.attrs.twitter_handle && sb.attrs.twitter_handle != '' ? <SocialFeedComp handle={sb.attrs.twitter_handle}/>
            : <p><i>Not yet implemented</i></p>
          }
        </section>)
      }
    </div>
}
