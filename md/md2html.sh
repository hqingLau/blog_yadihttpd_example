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
echo > ../index2.html
category=$(awk '{$1="";$2="";gsub(/^[ \t]+/,"");gsub(/[ \t]+/,"\n");print $0}' filename2name.txt | sed '/^[ \t]*$/d' | sort | uniq)
echo $category
# echo > ../blogCategory.html
# for c in $category; do
# 	echo -e "[$c](blog/category_${c}.html)\n" >> ../blogCategory.tmp
# done


echo "<?xml version=\"1.0\" encoding=\"utf-8\"?>
	<urlset xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\" xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\" xsi:schemaLocation=\"http://www.sitemaps.org/schemas/sitemap/0.9 http://www.sitemaps.org/schemas/sitemap/0.9/sitemap.xsd\">
	<url>
		<loc>https://orzlinux.cn/</loc>
		<priority>1.00</priority>
	</url>" > ../sitemap.xml

curTs=`date +%s`
for filename in $(ls -t);do 
	suffix=${filename##*.}; 
	if [ "$suffix" != "md" ]; then 
		continue;
	fi 
	name=${filename:0:${#filename}-3}

	filemodTime=`stat -c %Y $filename`
	timecha=$[$curTs - $filemodTime]

	if [[ ${dimap[${name}]} == "" ]]; then
		continue;
	fi
	# 如果24h内文件被修改
	if [[ $timecha -lt 60*60*12 || $updateAll -eq 1 ]]; then
		cat fakeTitleStart.html > ../blog/${name}.html
		chown pi:pi ../blog/${name}.html
		chown pi:pi ${filename}

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

	echo "
		<url>
			<loc>https://orzlinux.cn/blog/${name}.html</loc>
			<priority>1.00</priority>
		</url>
		" >> ../sitemap.xml
	
	ccc=$(stat -c %i $filename)
	dicrtime=$(sudo debugfs -R "stat <${ccc}>" /dev/vda1 | grep crtime)
	echo $(date '+%Y-%m-%d  &nbsp;&nbsp;' -d "${dicrtime:30:100}") >> tmp.mdfile
	echo -e "[${dimap[${name}]}](blog/${name}.html)\n" >> tmp.mdfile
done

echo "</urlset>" >> ../sitemap.xml
cat fakeTitleStart.html > ../index2.html
echo "主页" >> ../index2.html
cat fakeblog1.html >> ../index2.html
#echo "<h2>博客列表</h2><hr>" >> ../index2.html
marked -o tmpindex.html < tmp.mdfile
cat tmpindex.html >> ../index2.html
cat fakeblog2.html >> ../index2.html
echo "
	</body></html> " >> ../index2.html

chown pi:pi ../index2.html
echo "index built done"

rm ../index.html
mv ../index2.html ../index.html

######### 具体文件分类 ########
OLDIFS=$IFS
IFS=$'\n'
for line in $(tac filename2name.txt );do
	IFS=$' '
	arr=($line)
	ccc=$(stat -c %i ${arr[0]}.md)
	dicrtime=$(sudo debugfs -R "stat <${ccc}>" /dev/vda1 | grep crtime)
	for i in ${arr[@]:2};
	do
		secure_i=$(echo ${i/\//_})
		# if [[ ! $secure_i =~ ^[a-zA-Z0-9_]+$ ]] # 正则匹配多个输入的字符
		# then 
		# 	secure_i=$(trans :en -b ${secure_i})
		# 	sleep 5
		# fi
		secure_i=$(echo ${secure_i/ /_})
		echo $(date "+%Y-%m-%d  &nbsp;&nbsp;" -d "${dicrtime:30:100}") >> category_${secure_i}.tmp
		echo -e "[${arr[1]}](/blog/${arr[0]}.html)\n" >> category_${secure_i}.tmp
		
		echo -e "<a href=\"/blog/category_${secure_i}.html\" class="categorybutton" id=\"category_${secure_i}\">${i}</a>"  >> ../blogCategory.tmp
	done
	IFS=$'\n'
done
IFS=$OLDIFS
######### 具体文件分类结束 ########

# 总分类页面

cat ../blogCategory.tmp | sort | uniq > ../blogCategory.tmp2
buttonType="<!DOCTYPE html><html lang=\"zh\"><head><style>

	</style><title>"

echo $buttonType > ../blogCategory.html
echo "分类列表" >> ../blogCategory.html
cat fakeblog1.html >> ../blogCategory.html
#echo "<h2>博客列表</h2><hr>" >> ../index2.html
marked -o tmpindex2.html < ../blogCategory.tmp2
cat tmpindex2.html >> ../blogCategory.html
cat tmpindex.html >> ../blogCategory.html
cat fakeblog2.html >> ../blogCategory.html
echo "</body></html> " >> ../blogCategory.html
rm ../blogCategory.tmp
rm ../blogCategory.tmp2
chown pi:pi ../blogCategory.html
# ====分类页面结束===

# 具体分类页面
for c in $category; do
	secure_i=$(echo ${c/\//_})
	secure_c=$(echo ${secure_i/ /_})
	echo $buttonType > ../blog/category_${secure_c}.html
	echo "分类列表" >> ../blog/category_${secure_c}.html
	cat fakeblog1.html >> ../blog/category_${secure_c}.html
	#echo "<h2>博客列表</h2><hr>" >> ../index2.html
	# echo category_${secure_i}.tmp 
	marked -o tmpindex3.html < category_${secure_c}.tmp
	cat tmpindex2.html >> ../blog/category_${secure_c}.html
	cat tmpindex3.html >> ../blog/category_${secure_c}.html
	cat fakeblog2.html >> ../blog/category_${secure_c}.html


	echo "<script language=\"javascript\">
	document.getElementById(\"category_${secure_c}\").style.color=\"#6196cc\";
	</script></body></html> " >> ../blog/category_${secure_c}.html
	rm category_${secure_c}.tmp
	chown pi:pi ../blog/category_${secure_c}.html
done
# ====分类页面结束===

rm tmpindex.html
rm tmpindex2.html
rm tmpindex3.html
