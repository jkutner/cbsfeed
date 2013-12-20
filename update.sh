git pull origin gh-pages
bundle exec ruby update.rb
git add _data/*.yml
git commit -m "Updating with latest episdoes"
git push origin gh-pages

