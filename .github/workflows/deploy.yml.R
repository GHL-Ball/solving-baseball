name: Deploy Hugo site to Pages

on:
  push:
  branches: ["main"]
workflow_dispatch:
  
  permissions:
  contents: read
pages: write
id-token: write

jobs:
  build:
  runs-on: ubuntu-latest
steps:
  - uses: actions/checkout@v4
- name: Setup Hugo
uses: peaceiris/actions-hugo@v3
with:
  hugo-version: '0.152.2'
extended: true
- name: Build
run: hugo --minify
- name: Upload artifact
uses: actions/upload-pages-artifact@v3
with:
  path: ./public

deploy:
  environment:
  name: github-pages
url: ${{ steps.deployment.outputs.page_url }}
runs-on: ubuntu-latest
needs: build
steps:
  - name: Deploy to GitHub Pages
id: deployment
uses: actions/deploy-pages@v4
```

ファイルを作成したら、変更をプッシュします:
  ```
git add .
git commit -m "Add GitHub Actions workflow"
git push