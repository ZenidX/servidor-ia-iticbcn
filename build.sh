#!/usr/bin/env bash
# Genera index.html (GitHub Pages) a partir de propuesta.html
cd "$(dirname "$0")"
{ printf '<!doctype html>\n<html lang="es">\n<head>\n<meta charset="utf-8">\n<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">\n<style>body{margin:0}img{max-width:100%%}</style>\n'
  sed -n '1,/^<\/style>/p' propuesta.html; printf '</head>\n<body>\n'
  sed -n '/^<\/style>/,$p' propuesta.html | tail -n +2; printf '</body>\n</html>\n'; } > index.html
