# silicon.el

A convenience package for creating images of the current source buffer using Silicon <https://github.com/Aloxaf/silicon>. It requires you to have the `silicon` command-line tool installed and preferably on your path. You can specify the path to the executable by setting `silicon-executable-path`.

The package declares `silicon-buffer-file-to-png` which tries to create a PNG of the current source code buffer. See the function doc string for more details.

## How to load

First clone this repository.

### Using `require`

Add this to your config:

```emacs-lisp
(add-to-list 'load-path "<PATH TO DIRECTORY>")
(require 'silicon)
```

### Using `use-package`

``` emacs-lisp
  (use-package silicon
    :load-path "<PATH TO DIRECTORY>")
```
