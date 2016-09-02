
import express                   from 'express';
import url                       from 'url';
import http                      from 'http'
import React                     from 'react';
import { renderToString }        from 'react-dom/server'
import { Router, RouterContext, match }  from 'react-router';
import routes                    from './jsx/App.jsx';

const app = express();

app.use((req, res) => {
  var refURL = req.protocol + '://' + req.get('host') + req.originalUrl
  console.log("ISO fetch:", refURL)
  match({ routes: routes, location: req.url }, (err, redirectLocation, renderProps) => {
    if (err) { 
      console.error(err);
      return res.status(500).end('Internal server error');
    }
    if (!renderProps) return res.status(404).end('Not found.');
    var rc = <RouterContext {...renderProps} />
    var urls = []
    rc.props.location.urlsToFetch = urls
    var renderedHTML = renderToString(rc)
    if (urls.length == 0)
      res.send("<div id=\"main\">" + renderedHTML + "</div>")
    else if (urls.length == 1)
    {
      var partialURL = urls[0]
      var finalURL = url.resolve(refURL, partialURL).replace(":4002", ":4001")
      console.log("...integrating data from:", finalURL)

      http.get(finalURL, function(ajaxResp) {
        var body = '';
        ajaxResp.on('data', function(chunk) {
          body += chunk;
        });
        ajaxResp.on('end', function() {
          if (ajaxResp.statusCode == 200) {
            var response = JSON.parse(body)
            //console.log("Got a response:", response)
            delete rc.props.location.urlsToFetch
            rc.props.location.urlsFetched = {}
            rc.props.location.urlsFetched[partialURL] = response
            renderedHTML = renderToString(rc)
            res.send(
              "<script>window.jscholApp_initialPageData = " + body + ";</script>\n" +
              "<div id=\"main\">" + renderedHTML + "</div>")
          }
          else
            throw "HTTP Error " + ajaxResp.statusCode + ": " + body
        });
      }).on('error', function(e) {
        throw "HTTP Error " + e
      }); 
    }
    else
      throw "Internal error: currently support only one url in urlsToFetch"
  });
});

export default app;