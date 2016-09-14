
import React from 'react'
import { Link } from 'react-router'

import PageBase from './PageBase.jsx'
import { HeaderComp, NavComp, FooterComp } from '../components/AllComponents.jsx'

class ItemPage extends PageBase
{
  // PageBase will fetch the following URL for us, and place the results in this.state.pageData
  pageDataURL(props) {
    return "/api/item/" + props.params.itemID
  }

  render() { return(
    <div>
      { this.state.pageData ? this.renderData(this.state.pageData) : <div>Loading...</div> }
      <FooterComp />
    </div>
  )}

  renderData(data) { return(
    <div>
       {/* ToDo: find parent campus and unit */}
      <HeaderComp level="item"
                  campus=""
                  unit_id="" />
      <NavComp level="item"
               unit_id = "" />
       <p dangerouslySetInnerHTML={{__html: data.breadcrumb}}></p>
      <h2 style={{ marginTop: "5em", marginBottom: "5em" }}>Item page content here</h2>
    </div>
  )}
}

module.exports = ItemPage;