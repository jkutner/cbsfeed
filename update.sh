#source /home/tmux/.rvm/environments/ruby-1.9.3-p448

cd /home/tmux/cbsfeed

git pull origin gh-pages
echo "Running the update script with bundler..."
ruby update.rb 
echo "Updating git repo..."
git add _data/*.yml
git commit -m "Updating with latest episdoes"
git push origin gh-pages
echo "All done!"

