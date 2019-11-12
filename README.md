# HSHTMLImageRenderer-swift
A re-incarnated version of my previous project, this time in Swift and using `WKWebView` instead of the now deprecated `UIWebView`.

`HSHTMLImageRenderer` was designed to render small snippets of HTML to an image file, and optionally cache that image.  It's for specific use cases obviously, but basically where your HTML is more complex than a `UILabel` can handle, but you have a lot of content so just rendering lots of snippets in lots of `WKWebView` objects could become a performance problem.

As they say, render once then cache.  A `WKWebView` is a bit of a black box, and has a lot of overhead.  The first snippet you would render could take 0.4s, which comes down to 0.15s or so once you make more `-loadHTMLString:baseURL:` calls.

This class is a little dirty in its approach, but at least it's self-contained.  That's all we as programmers can ask of anything smelly...

`HSHTMLImageRenderer` wraps an `OperationQueue` and has `Operation`s that take care of all the work.  Unfortunately it can't all be done in the background because `UIKit`/`WebKit` classes need to have their methods called from the main thread.  So the actual method call of generating an image of the `WKWebView` is done on the main thread.  You may need to find a good strategy for generating this cached content.  You can't avoid the performance hit, but you CAN minimize it.  This class has a `suspended` property that wraps that same property on the `OperationQueue`.  Consider setting this to `true` when you are scrolling through a `UITableView` or `UICollectionView` for a massively improved user experience.

Ultimately the images are in a `NSCache` against the `identifier` property as a key.

Have a look at `ViewController.swift` in the `HTMLRendererDemo` target to get an idea of how to use the class.

The hacky part of this is that we use a `WKWebView`, but in order for it to render properly, it needs to belong to a view hierarchy.  This is why you initialize the renderer with a `UIWindow` object.  It assumes you have a relatively typical iOS project in that your `UIWindow` has a `rootViewController`.  As such, it inserts this 'rendering webview' at the very back of the view hierarchy, behind your rootViewController.

## Installation

-- Write New Documentation here! --

This isn't meant to be a Library.  There is a Cocoapod, but should there be?  It's an approach.  Your specific needs will be different, so it offers a starting point.  To see how it's done, but it's up to you to extend the functionality for your project's needs.  You'll find I've provided arguments for each method that actually have in this implementation one possible value.  The idea is that the stub is there... you just have to add to it.

## On Performance...

Because it uses the main thread to render the content, this often conflicts with the queueing systems of `UITableView` and `UICollectionView` who will often call `-cellFor(Row/Item)AtIndexPath:` while you are scrolling, which will mean in most cases you'll want to populate that cell, in which case you'll make a call to the renderer, then you're left with a big party on the main thread and the UI turns into to a slow, jittery mess.

I've found that putting this in your `UIViewController` subclass (or whichever class is your `UIScrollViewDelegate` of the table or collection view), is what makes your UI happy again.

```
#pragma mark - ScrollView Delegate

- (void)scrollViewDidScroll:(UIScrollView *)scrollView
{
  if (scrollView.isTracking) {
    [[HSHTMLImageRenderer rendererInWindow:self.view.window] setSuspended:YES];
  }
}

- (void)scrollViewDidEndScrollingAnimation:(UIScrollView *)scrollView
{
  [[HSHTMLImageRenderer rendererInWindow:self.view.window] setSuspended:NO];
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView
{
  [[HSHTMLImageRenderer rendererInWindow:self.view.window] setSuspended:NO];
}
```

## License

As such, this is all MIT License.  You know, the one where you can't sue me because you don't like something or your code broke or whatever.  I'd put it on the Beerware license, but you should never force someone to gift you a beer.  It should always come from the heart.  ;)

## About

Stephen O'Connor has been developing on iOS since iPhone OS 3.0.  He has an internet presence at [http://horseshoe7.wordpress.com](http://horseshoe7.wordpress.com), and is generally for hire, if you can manage to find him in available in this world of high demand for experienced iOS Developers.  Nevertheless, emails to `oconnor.freelance@gmail.com` may bear some fruit.
