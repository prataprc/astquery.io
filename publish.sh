CURRDIR=`pwd`
DIRGHPAGES="/tmp/gh-pages"
rm -rf $DIRGHPAGES
git clone . $DIRGHPAGES
cd $DIRGHPAGES
git remote remove origin
git remote add origin git@github.com:prataprc/astquery.io.git
git branch -D gh-pages
git push origin --delete gh-pages
git checkout -b gh-pages
rm -rf $DIRGHPAGES/*
cp -R $CURRDIR/_site/* .
git add .
git commit -m "publish"
git push origin gh-pages:gh-pages
