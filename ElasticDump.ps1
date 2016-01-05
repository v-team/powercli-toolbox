$i=0
$pre = '{"fields" : ["message"],"from":'
$post = ',"size": 2000,"query":{"filtered":{"query":{"bool":{"should":[{"query_string":{"query":"hostname.raw:esx.vmware.com"}}]}},"filter":{"bool":{"must":[{"range":{"@timestamp":{"from":1450738800000,"to":1450997999999}}}]}}}}}'
$msgs=1

while ($msgs) {
$msgs=$false
$body = $pre + $i + $post
$msgs=(Invoke-RestMethod -URI "http://demo.sexilog.fr:9200/_search?pretty=1" -Method 'POST' -ContentType 'application/json' -Body $body -TimeoutSec 5).hits.hits.fields.message
$msgs|%{$_.Trim()}|Out-File -FilePath c:\temp\esx.vmware.com.log -Append
$i=$i+2000
}
