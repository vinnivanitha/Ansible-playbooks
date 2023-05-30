#!/bin/sh
logfile="/opt/mcp/log/billing.log"
commondbip=`cat /opt/mcp/billing/billing.conf | grep commondbip`
commondbip=$(awk -F= '{print $2}' <<< $commondbip)
subscriptionrates="/opt/mcp/billing/subscriptionrates"
sftppassword=`cat /opt/mcp/billing/billing.conf | grep sftppassword`
sftppassword=$(awk -F= '{print $2}' <<< $sftppassword)
defaultbillablesubscription=`cat /opt/mcp/billing/billing.conf | grep defaultbillablesubscription`
defaultbillablesubscription=$(awk -F= '{print $2}' <<< $defaultbillablesubscription)
commondbpasswaord=`/bin/sh /opt/cdrtool/bin/getDatabaseInfo.sh common_production | awk -F"|" '{print $5}'`
#opennmsdbpassword=`cat /opt/mcp/billing/billing.conf | grep opennmsdbpassword`
#opennmsdbpassword=$(awk -F= '{print $2}' <<< $opennmsdbpassword)
#cost=`PGPASSWORD=$opennmsdbpassword psql -h 127.0.0.1 -U postgres -d opennms -t -c "select orgname,subscription from billingcharges where  (orgname,timestamp) IN (select orgname,MAX(timestamp) from billingcharges group by orgname);" | tr -d ' '`
cost=`PGPASSWORD=$commondbpasswaord psql -h $commondbip -U postgres -d mcp_production -p 5432 -t -c "select orgid,rate from billing_charges where  (orgid,updated_at) IN (select orgid,MAX(updated_at) from billing_charges where type_of_charges='Subscription' group by orgid);" | tr -d ' '`
echo "$cost" > $subscriptionrates
while read line 
do
    if [ "$line" != "" ] ; then
	declare -A REPLACE_MAP
	org=$(awk -F"|" '{ print $1}' <<< $line)
	cost=$(awk -F"|" '{ print $2}' <<< $line)
	REPLACE_MAP[$org]=$cost
    fi
done < $subscriptionrates

echo "`date` :: Origination charges configured in database " >> $logfile
for key in "${!REPLACE_MAP[@]}"; do
    echo "`date` :: Org = $key  and price = ${REPLACE_MAP["$key"]}" >> $logfile
done

billable_org=`/bin/sh /opt/mcp/billing/createlist.sh -1 Billable`
IFS=$'\n'
declare -A ORG_PRICE_MAP
for var in $billable_org
do
        org=$(awk -F'(' '{print $1}' <<< $var)

	#Get list based on earch org
	#orglist=`/bin/sh /opt/mcp/billing/createlist.sh $org All`
	orglist=$org
	for i in $orglist; do 
		ORG_PRICE_MAP[$i]=${REPLACE_MAP["$org"]}
	done
done

echo "`date` :: Origination charges configured for all orgs" >> $logfile
for key in "${!ORG_PRICE_MAP[@]}"; do
    if [[ ${ORG_PRICE_MAP["$key"]} == '' ]] ; then
	ORG_PRICE_MAP["$key"]="$defaultbillablesubscription"	
    fi
    echo "`date` ::  Org = $key and price = ${ORG_PRICE_MAP["$key"]}" >> $logfile
done


orgid=`cat /opt/mcp/billing/billing.conf | grep orgid`
orgid=$(awk -F= '{print $2}' <<< $orgid)
send_status=1
error_status=0
date=`date`
IFS=$','
#Loop for each org
for i in $orgid; do
orgid=$i
echo "$date :: Process for org "$orgid >> $logfile

echo "$date :: Start execution of billing process " >> $logfile
password=`cat /opt/mcp/billing/billing.conf | grep servicepassword`
password=$(awk -F= '{print $2}' <<< $password)
#keypath=`cat /opt/mcp/billing/billing.conf | grep sftpserverkeypath`
#keypath=$(awk -F= '{print $2}' <<< $keypath)
sftpip=`cat /opt/mcp/billing/billing.conf | grep sftpserverip`
sftpip=$(awk -F= '{print $2}' <<< $sftpip)
sftpport=`cat /opt/mcp/billing/billing.conf | grep sftpport`
sftpport=$(awk -F= '{print $2}' <<< $sftpport)
#originationcharges=`cat /opt/mcp/billing/billing.conf | grep originationcharges`
#originationcharges=$(awk -F= '{print $2}' <<< $originationcharges)
xmlstoragepath=`cat /opt/mcp/billing/billing.conf | grep xmlstoragepath`
xmlstoragepath=$(awk -F= '{print $2}' <<< $xmlstoragepath)
offload=`cat /opt/mcp/billing/billing.conf | grep offload`
xmloffload=$(awk -F= '{print $2}' <<< $offload)
if [ ! -e $xmlstoragepath ]
then
	`mkdir -p $xmlstoragepath`
fi
if [ "$password" == "" ]
then
	echo "`date` :: Please check if password is configured or not properly in config file, exiting the script."  >> $logfile
	exit
fi

echo "`date` :: DBIP = $commondbip"  >> $logfile
if [ "$commondbip" == "" ]
then
	echo "`date` :: Please check if common db ip is configured or not properly in config file, exiting the script."  >> $logfile
	exit
fi
#Execution of org-hierarchy
#url_string="http://172.16.1.141:8000/mcp/mcpwebapi/organizations/list_org_hierarchy?userid=1&password=personnel&format=xml&get_count=true"
xmlpath=`cat /opt/mcp/billing/billing.conf | grep xmlstoragepath`
xmlpath=$(awk -F= '{print $2}' <<< $xmlpath)
if [ $orgid == "-1" ]
then
	url_string="http://"$commondbip":8000/mcp/mcpwebapi/organizations/list_org_hierarchy?userid=1&password="$password"&system_id=1&format=xml&get_sls_count=true"
	filename="$xmlpath""org-hierarchy-systemwide-"`date '+%Y%m%d%H%M%S.xml'`
else
	url_string="http://"$commondbip":8000/mcp/mcpwebapi/organizations/list_org_hierarchy?userid=1&password="$password"&system_id=1&format=xml&get_sls_count=true&orgid="$orgid
	filename="$xmlpath""org-hierarchy-$orgid-"`date '+%Y%m%d%H%M%S.xml'`
fi
echo "`date` :: Org-hierarchy URL = $url_string" >> $logfile
#xmlpath=`cat /opt/mcp/billing/billing.conf | grep xmlstoragepath`
#xmlpath=$(awk -F= '{print $2}' <<< $xmlpath)
date=`date`
#filename="$xmlpath""org-hierarchy-$orgid-"`date '+%Y%m%d%H%M%S.xml'`
xml_output=`curl "$url_string"`
#echo "`date` :: Http response $xml_output" >> $logfile
echo "`date` :: Store response in $filename file" >> $logfile
echo "$xml_output" > $filename
`sed -i '/<monitor-sms-enabled>/d' $filename`
`sed -i '/<monitor-call-enabled>/d' $filename`
`sed -i 's/<billing-plan-id><\/billing-plan-id>/<billing-plan-id>0000<\/billing-plan-id>/g' $filename`
echo "`date` :: Replace system id value in $filename file" >> $logfile
systemid=`cat /opt/mcp/billing/billing.conf | grep systemid`
systemid=$(awk -F= '{print $2}' <<< $systemid)
sed -i '2s/Movius US/'"$systemid"'/'  $filename
defaultorgsubscription=`cat /opt/mcp/billing/billing.conf | grep defaultorgsubscription`
defaultorgsubscription=$(awk -F= '{print $2}' <<< $defaultorgsubscription)
sed -i 's/subscription>20<\/subscription/subscription>'"$defaultorgsubscription"'<\/subscription/g' $filename
#Remove special characters
grep -n "<name>" $filename | while read -r row_num ; do
        line_num=$(awk -F":" '{ print $1}' <<< $row_num)
        `sed -i "${line_num}s/[^<name>a-zA-Z0-9 <\/name>]//g" $filename`
done
if [ -e $filename ] 
then
	error_status=`grep "return_message" $filename | wc -l`
	echo $error_status
	if [[ $error_status -gt 0 ]]
	then
		echo "`date` :: Please check xml response, looks like something is going wrong" >> $logfile
                send_status=-1
	else
		echo "`date` :: Set subscription charges of Orgs " >> $logfile	
		for key in "${!ORG_PRICE_MAP[@]}"; do
		    row=$(awk -F":" '{ print $1}' <<< `grep -n "<id>$key</id>" $filename` )
		    row_to_be_updated=$((row+1))
		    `sed -i "${row_to_be_updated}s/<subscription>"$defaultorgsubscription"</<subscription>${ORG_PRICE_MAP[$key]}</" $filename  `
		done

	fi
	#for row_num in $(awk -F":" '{ print $1}' <<< `grep -n "billable>false<" $filename` )
	i=0
        grep -n "billable>false<" $filename | while read -r row_num ; do
               echo $row_num
               line_num=$(awk -F":" '{ print $1}' <<< $row_num)
	       echo $line_num
               line_num=$((line_num-5-i))
               `sed -i "${line_num}d" $filename`
               #echo "Going to delete $line_num line"
	       i=$((i+1))
        done

	echo "`date` :: SFTP the $filename file to billing server." >> $logfile
	if [[ $xmloffload == "true" &&  $send_status == 1 ]] ; then
	#eval $(ssh-agent) ; ssh-add  $keypath
	orgxmlsftpdestinationpath=`cat /opt/mcp/billing/billing.conf | grep orgxmlsftpdestinationpath`
	destination=$(awk -F= '{print $2}' <<< $orgxmlsftpdestinationpath)
	expect << EOS
	spawn sftp -o StrictHostKeyChecking=no movius@$sftpip:$destination 
	expect "Password:"
	send "$sftppassword\n" 
	expect "sftp>"
	send "put $filename\n" 
	expect "sftp>"
	send "bye\n"
EOS
	else
	echo "`date` :: SFTP is disable and send_status=$send_status" >> $logfile
	fi
fi

#Create origination xml using api request
#http://172.16.1.141:8000/mcp/mcpwebapi/sls_numbers/org_origination?userid=1&password=personnel&format=xml
#url_string="http://"$commondbip":8000/mcp/mcpwebapi/sls_numbers/origination_charges?userid=1&password="$password"&format=xml"
#echo "`date` :: Origination URL = $url_string" >> $logfile
#filename="$xmlpath""origination-"`date '+%Y%m%d%H%M%S.xml'`
#xml_output=`curl "$url_string"`
#echo "`date` :: Http response $xml_output" >> $logfile
#echo "`date` :: Store response in $filename file" >> $logfile
#echo "$xml_output" > $filename
#sed -i '2s/origination/origination-charges/'  $filename
#sed -i '2s/Movius US/'"$systemid"'/'  $filename
#if [ -e $filename ]
#then
#        while read line; do
#             if [[ $line =~ "return_message" ]] ; then
#                echo "`date` :: Please check xml response, looks like something is going wrong" >> $logfile
#             fi
#        done < $filename
#        echo "`date` :: SFTP the $filename file to billing server." >> $logfile
#        eval $(ssh-agent) ; ssh-add  $keypath
#        originationxmlsftpdestinationpath=`cat /opt/mcp/billing/billing.conf | grep originationxmlsftpdestinationpath`
#        destination=$(awk -F= '{print $2}' <<< $originationxmlsftpdestinationpath)
#	sftp -o Port=$sftpport movius@$sftpip << EOF
#        put $filename $destination
#EOF
#echo "`date` :: End of execution process." >> $logfile
#fi

#Create origination xml using input file
#echo "`date` :: Start execution for Origination charges" >> $logfile
#filename="$xmlpath""origination-$orgid-"`date '+%Y%m%d%H%M%S.xml'`
#if [ ! -e /opt/mcp/billing/originationinput.txt ]
#then
#       echo "`date` :: Config file is not present" >> $logfile
#	`touch /opt/mcp/billing/originationinput.txt`
#fi

#Read file to get list of service providers
#provider_list=`awk -F',' '(NR>1){print $1}'  /opt/mcp/billing/originationinput.txt | sort |uniq | tr '\n' ':'`
#echo "Provider list - "$provider_list >> $logfile
#
#Fetch data for each provider from config file

#echo "<?xml version=\"1.0\" encoding=\"UTF-8\"?>"  >> $filename

#echo "<origination-charges system-id=\"Movius US\">"  >> $filename
#for i in ${provider_list//:/ }
#do
#        echo "Service Provider name :::: $i" >> $logfile
#        echo "  <provider>" >> $filename
#        echo "     <name>$i</name>" >> $filename
#        echo "$xml_str"
#	country_list=`awk -F',' '(NR>1){print $2}'  /opt/mcp/billing/originationinput.txt | sort | uniq | tr '\n' ':'`
#        #while read country; do
#	for country_name in ${country_list//:/ }
#	do
#                #if [[ $country =~ $i ]]
#                #then
#                        country_name=`awk -F',' '{print $2}' <<< $country`
#				#if [ `cat /opt/mcp/billing/originationinput.txt | grep "$i,$country_name" | wc -l ` -gt 0 ]
#				#then 
#                       	#echo "          <country>" >> $filename
#	                	#echo "               <name>$country_name</name>" >> $filename
#		                #echo "               <charges>$originationcharges</charges>" >> $filename
#        	               	#echo "               <org-mapping>" >> $filename
#				#fi
#				#echo "Process for Country :::: $country_name " >> $logfile
#                               #while read orgcount; do
#                                #        if [[ "$orgcount" =~ "$country_name" && "$orgcount" =~ "$i" ]]
#                                #        then
#                                #                org_name=`awk -F',' '{print $3}' <<< $orgcount`
#                                #                org_count=`awk -F',' '{print $4}' <<< $orgcount`
#                                #                echo "                 <org>" >> $filename
#                                #                echo "                    <org-id>$org_name</org-id>" >> $filename
#                                #                echo "                    <count>$org_count</count>" >> $filename
#                                #                echo "                 </org>" >> $filename
#                                #        fi
#                                #done < /opt/mcp/billing/originationinput.txt
#				#if [ `cat /opt/mcp/billing/originationinput.txt | grep "$i,$country_name" | wc -l ` -gt 0 ]
#				#then 
#                       		#echo "               </org-mapping>" >> $filename
#			        #echo "          </country>" >> $filename
#				#fi
#
#                #fi
#        #done < /opt/mcp/billing/originationinput.txt
#	done
#        echo "  </provider>" >> $filename
#done
#echo "</origination-charges>"  >> $filename
#sed -i '2s/Movius US/'"$systemid"'/'  $filename
#echo "`date` :: Store response in $filename file" >> $logfile
#echo "`date` :: SFTP the $filename file to billing server." >> $logfile
#if [[ $xmloffload == "true" ]] ; then
#originationxmlsftpdestinationpath=`cat /opt/mcp/billing/billing.conf | grep originationxmlsftpdestinationpath`
#destination=$(awk -F= '{print $2}' <<< $originationxmlsftpdestinationpath)
#        expect << EOS
#        spawn sftp -o StrictHostKeyChecking=no movius@$sftpip:$destination
#        expect "Password:"
#        send "MzAz3hlfTWbUtOl3Mexh\n"
#        expect "sftp>"
#        send "put $filename\n"
#        expect "sftp>"
#        send "bye\n"
#EOS
#else
#        echo "`date` :: SFTP is disable" >> $logfile
#fi

#COMMENT
#done looping for Org
done
