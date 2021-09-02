#!/bin/bash
# 要更新全部，用参数--all
# 如：md2html.sh --all
# allmd=$(find ./ -name '*.md' -type f -mmin -60 -exec basename {} \;)
cd /home/pi/www/md
declare -A dimap;
if [[ $# -eq 1 && $1 == "--all" ]]; then
	updateAll=1
fi
eval `awk '{printf("dimap[%s]=%s;",$1,$2)}' filename2name.txt`
echo > tmp.mdfile
echo > ../index.html
curTs=`date +%s`
for filename in $(ls -t);do 
	suffix=${filename##*.}; 
	if [ "$suffix" != "md" ]; then 
		continue;
	fi 
	name=${filename:0:${#filename}-3}

	filemodTime=`stat -c %Y $filename`
	timecha=$[$curTs - $filemodTime]

	# 如果24h内文件被修改
	if [[ $timecha -lt 60*60*48 || $updateAll -eq 1 ]]; then
		cat fakeTitleStart.html > ../blog/${name}.html
		chown pi:pi ../blog/${name}.html
		chown pi:pi ${filename}
		if [[ ${dimap[${name}]} == "" ]]; then
			continue;
		fi
		echo ${dimap[${name}]} >> ../blog/${name}.html
		cat fakeblog1.html >> ../blog/${name}.html
		marked -o ../blog/tmp${name}.html < ${filename}
		echo "<h1>${dimap[$name]}</h1><hr>">> ../blog/${name}.html
		cat ../blog/tmp${name}.html >> ../blog/${name}.html
		rm ../blog/tmp${name}.html
		cat fakeblog2.html >> ../blog/${name}.html
		echo "
    <script type=\"text/javascript\">
    document.getElementById(\"banquan-yadi\").style.display =\"\";
  document.getElementById(\"blogaddr-a\").href =\"https://orzlinux.cn/blog/\"+\"${name}.html\";
  document.getElementById(\"blogaddr-a\").innerHTML=\"${dimap[${name}]}\";
</script></body></html> " >> ../blog/${name}.html
       		echo "${filename}:${dimap[${name}]}  to html done."
	fi

	echo $(date '+%Y-%m-%d  &nbsp;&nbsp;' -d @$(stat -c %Y $filename)) >> tmp.mdfile
	echo -e "[${dimap[${name}]}](blog/${name}.html)\n" >> tmp.mdfile
done
cat fakeTitleStart.html > ../index.html
echo "博客列表" >> ../index.html
cat fakeblog1.html >> ../index.html
#echo "<h2>博客列表</h2><hr>" >> ../index.html
marked -o tmpindex.html < tmp.mdfile
cat tmpindex.html >> ../index.html
rm tmpindex.html
cat fakeblog2.html >> ../index.html
echo "
</body></html> " >> ../index.html
  echo "index built done"
