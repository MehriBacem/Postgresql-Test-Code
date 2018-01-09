#!/bin/sh



docker run --name ali -d postgres

docker exec ali psql -U postgres -c 'Create database test1;'
docker exec ali psql -U postgres -c '\c test1;'
docker exec ali psql -U postgres -c 'create or replace function test() returns void language sql as $f$


DROP table  IF EXISTS doc_tags_id;
DROP table  IF EXISTS doc_tags_text;
DROP table IF EXISTS doc_tags_json;
DROP table IF EXISTS doc_tags_array;
DROP table IF EXISTS tags;

create table tags ( tag_id serial not null primary key, tag text not null unique);
CREATE table doc_tags_text (
doc_id int not null,
tag text not null );

create index doc_tags_text_tag on doc_tags_text(tag) ;

create table doc_tags_id (doc_id int not null,tag_id int not null references tags(tag_id));
create index doc_tags_id_tag_id on doc_tags_id(tag_id);

 
create  table doc_tags_json (doc_id int not null,tags jsonb);
create index doc_tags_id_tags on doc_tags_json using gin(tags);

create table doc_tags_array (doc_id int not null,tags text[] not null );
create index doc_tags_id_tags_array on doc_tags_array using gin(tags);
$f$;'

docker exec ali psql -U postgres -c 'select test();'


docker exec ali psql -U postgres -c "CREATE OR REPLACE FUNCTION random_text(INTEGER) RETURNS TEXT LANGUAGE SQL AS \$$
SELECT array_to_string(array(SELECT SUBSTRING('23456789abcdefghjkmnpqrstuvwxyz' FROM floor(random()*31)::int+1 FOR 1) FROM 
generate_series(1,\$1)), '');\$$;"
docker exec ali psql -U postgres -c 'create or replace function geornd_10() returns int language sql as $f$
select round(log(random()::numeric)/log(0.3))::INT + 1;
$f$;'
docker exec ali psql -U postgres -c 'create or replace function geornd_100()
returns int
language sql
as $f$
select round(log(random()::numeric)/log(0.9))::INT + 1;
$f$;'

docker exec ali psql -U postgres -c "CREATE or REPLACE FUNCTION tags() RETURNS void AS \$$
DECLARE 
      str text;
      iter INT ;
BEGIN 

  INSERT INTO tags(tag) VALUES('technology');
INSERT INTO tags(tag) VALUES('math');
   
     FOR  iter IN 3..99 LOOP


   SELECT INTO str random_text(5) ;
 
  INSERT INTO tags(tag) VALUES(str);
   END LOOP;

INSERT INTO tags(tag) VALUES('thrift shop');
INSERT INTO tags(tag) VALUES ('blogging');

 FOR  iter IN 102..160 LOOP


   SELECT INTO str random_text(5) ;
 
  INSERT INTO tags(tag) VALUES(str);
   END LOOP;
RETURN;
END;
\$$ LANGUAGE plpgsql;"

docker exec ali psql -U postgres -c 'select tags();'
docker exec ali psql -U postgres -c 'select * from tags limit 25;'

docker exec ali psql -U postgres -c "CREATE or REPLACE FUNCTION test_scalability() RETURNS void AS \$$
DECLARE 
      str text;
       compt INT ;
number INT;
number1 INT;
         iter INT ;
           T  TEXT[];
     name TEXT;
      
BEGIN 
     FOR  iter IN 1..1000000 LOOP
        
          
   SELECT INTO number  geornd_10() ;
 
              FOR iter1 IN 1.. number LOOP
    SELECT INTO number1  geornd_100() ;
SELECT    tag into name from tags where tag_id= number1 ;   
                                    
            INSERT INTO doc_tags_text(doc_id,tag) VALUES(iter,name);
    
        
          INSERT INTO doc_tags_id(doc_id,tag_id) VALUES(iter,number1);

                 SELECT INTO T  array_append(T,name) ;
          END LOOP;
    
        INSERT INTO doc_tags_json(doc_id,tags) VALUES(iter,array_to_json(T)::jsonb);
       INSERT INTO doc_tags_array(doc_id,tags) VALUES(iter,T);
         T := '{}';

      END LOOP;
RETURN;
END;
\$$ LANGUAGE plpgsql;"

docker exec ali psql -U postgres -c 'select test_scalability();'



echo "************************* Check size ***********************"

docker exec ali psql -U postgres -c 'select relname, pg_size_pretty(pg_total_relation_size(relid)) from pg_stat_user_tables;'

echo " **************************Test 1 : Time required to retrieve all the tags for a single document(1tag)******************"

echo "*************Text*********"

docker exec ali psql -U postgres -c 'EXPLAIN ANALYZE select tag from doc_tags_text where doc_id=(select doc_id from doc_tags_array where cardinality(tags)=1 limit 1) ;'

echo "************Array Text***********"
docker exec ali psql -U postgres -c 'EXPLAIN ANALYZE select tags from doc_tags_array where doc_id=(select doc_id from doc_tags_array where cardinality(tags)=1 limit 1) ;'

echo "***************JSONB***********"
docker exec ali psql -U postgres -c'EXPLAIN ANALYZE select tags from doc_tags_json where doc_id=(select doc_id from doc_tags_array where cardinality(tags)=1 limit 1) ;'

echo "*****************ID***************"
docker exec ali psql -U postgres -c 'EXPLAIN ANALYZE select tag from tags,doc_tags_id where doc_tags_id.doc_id=(select doc_tags_id.doc_id from doc_tags_array where cardinality(tags)=1 limit 1) AND tags.tag_id=doc_tags_id.tag_id ;'

echo " *****************Test 1 : Time required to retrieve all the tags for a single document(9tags)******************"

echo "*************Text*********"

docker exec ali psql -U postgres -c 'EXPLAIN ANALYZE select tag from doc_tags_text where doc_id=(select doc_id from doc_tags_array where cardinality(tags)=9 limit 1) ;'

echo "************Array Text***********"
docker exec ali psql -U postgres -c 'EXPLAIN ANALYZE select tags from doc_tags_array where doc_id=(select doc_id from doc_tags_array where cardinality(tags)=9 limit 1) ;'

echo "***************JSONB***********"
docker exec ali psql -U postgres -c'EXPLAIN ANALYZE select tags from doc_tags_json where doc_id=(select doc_id from doc_tags_array where cardinality(tags)=9 limit 1) ;'

echo "*****************ID***************"
docker exec ali psql -U postgres -c 'EXPLAIN ANALYZE select tag from tags,doc_tags_id where doc_tags_id.doc_id=(select doc_tags_id.doc_id from doc_tags_array where cardinality(tags)=9 limit 1) AND tags.tag_id=doc_tags_id.tag_id ;'


echo " **************Test 2 : Time required to retrieve the first page of 25 results for a common tag**************"

echo "***************JSONB***********"
docker exec ali psql -U postgres -c "EXPLAIN ANALYZE select doc_id  from doc_tags_json where tags @> '[\"math\"]'::jsonb  order by doc_id limit 25 offset 0;"

echo "************Array Text***********"
docker exec ali psql -U postgres -c "EXPLAIN ANALYZE select doc_id from doc_tags_array  where tags @> ARRAY['math'] order by doc_id limit 25 offset 0;" 

echo "*************Text*********"

docker exec ali psql -U postgres -c "EXPLAIN ANALYZE select doc_id from doc_tags_text where tag='math' order by doc_id limit 25 offset 0;"

echo "*****************ID***************"
docker exec ali psql -U postgres -c "EXPLAIN ANALYZE select doc_id from  doc_tags_id,tags where tag='math' AND doc_tags_id.tag_id=tags.tag_id order by doc_id limit 25 offset 0;"

echo " *****************Test 2 : Time required to retrieve the 10th page of 25 results for a common tag**********"

echo "***************JSONB***********"
docker exec ali psql -U postgres -c "EXPLAIN ANALYZE select doc_id  from doc_tags_json where tags @> '[\"math\"]'::jsonb  order by doc_id limit 25 offset 250;"

echo "************Array Text***********"
docker exec ali psql -U postgres -c "EXPLAIN ANALYZE select doc_id from doc_tags_array  where tags @> ARRAY['math'] order by doc_id limit 25 offset 250;" 

echo "*************Text*********"

docker exec ali psql -U postgres -c "EXPLAIN ANALYZE select doc_id from doc_tags_text where tag='math' order by doc_id limit 25 offset 250;"

echo "*****************ID***************"
docker exec ali psql -U postgres -c "EXPLAIN ANALYZE select doc_id from  doc_tags_id,tags where tag='math' AND doc_tags_id.tag_id=tags.tag_id order by doc_id limit 25 offset 250;"

echo " **************Test 3 : Time required to retrieve the first page of 25 results for a uncommon tag***************"

echo "***************JSONB***********"
docker exec ali psql -U postgres -c "EXPLAIN ANALYZE select doc_id  from doc_tags_json where tags @> '[\"blogging\"]'::jsonb  order by doc_id limit 25 offset 0;"

echo "************Array Text***********"
docker exec ali psql -U postgres -c "EXPLAIN ANALYZE select doc_id from doc_tags_array  where tags @> ARRAY['blogging'] order by doc_id limit 25 offset 0;" 

echo "*************Text*********"


docker exec ali psql -U postgres -c "EXPLAIN ANALYZE select doc_id from doc_tags_text where tag='blogging' order by doc_id limit 25 offset 0;"

echo "******************ID****************"
docker exec ali psql -U postgres -c "EXPLAIN ANALYZE select doc_id from  doc_tags_id,tags where tag='blogging' AND doc_tags_id.tag_id=tags.tag_id order by doc_id limit 25 offset 0;"

echo " **********************Test 3 : Time required to retrieve the Two tags combined (common tags)********************"
echo "*************Text*********"

docker exec ali psql -U postgres -c"EXPLAIN ANALYZE select doc_id from doc_tags_text dt1 join doc_tags_text dt2 using (doc_id) where dt1.tag = 'technology' and dt2.tag = 'math' order by doc_id limit 25;" 
echo "***********ID***********"
docker exec ali psql -U postgres -c "EXPLAIN ANALYZE select di1.doc_id from doc_tags_id di1 join doc_tags_id di2 on di1.doc_id = di2.doc_id
join tags tags1 on di1.tag_id = tags1.tag_id join tags tags2 on di2.tag_id = tags2.tag_id
where tags1.tag = 'technology' and tags2.tag = 'math' order by di1.doc_id limit 25;"

echo "************Array Text***********"
docker exec ali psql -U postgres -c "EXPLAIN ANALYZE select doc_id  from doc_tags_array where tags @> array['math','technology'] order by doc_id limit 25;"
echo "***********JSONB***********"
docker exec ali psql -U postgres -c "EXPLAIN ANALYZE with find_docs as (select doc_id from doc_tags_json where tags @> '[\"technology\", \"math\"]')                        
select * from find_docs order by doc_id limit 25;"

echo " *************Test 3 : Time required to retrieve the Two tags combined (rare tags)***************"
echo "************Text***********"
docker exec ali psql -U postgres -c"EXPLAIN ANALYZE select doc_id from doc_tags_text dt1 join doc_tags_text dt2 using (doc_id) where dt1.tag = 'blogging' and dt2.tag = 'thrift shop' order by doc_id limit 25;" 
echo "************ID***********"
docker exec ali psql -U postgres -c "EXPLAIN ANALYZE select di1.doc_id from doc_tags_id di1 join doc_tags_id di2 on di1.doc_id = di2.doc_id
join tags tags1 on di1.tag_id = tags1.tag_id join tags tags2 on di2.tag_id = tags2.tag_id
where tags1.tag = 'blogging' and tags2.tag = 'thrift shop' order by di1.doc_id limit 25;"
echo "************Array Text***********"
docker exec ali psql -U postgres -c "EXPLAIN ANALYZE select doc_id  from doc_tags_array where tags @> array['blogging','thrift shop'] order by doc_id limit 25;"
echo "************JSONB***********"
docker exec ali psql -U postgres -c "EXPLAIN ANALYZE with find_docs as (select doc_id from doc_tags_json where tags @> '[\"thrift shop\", \"blogging\"]')                        
select * from find_docs order by doc_id limit 25;"

echo " ***********************Test 4 :  pulling counts of all distinct tags and then taking the top 100*************"
echo "************JSONB***********"
docker exec ali psql -U postgres -c "EXPLAIN ANALYZE select count(*) as tag_count, tag from doc_tags_json join tags on doc_tags_json.tags @> to_json(tags.tag)::jsonb  group by tag order by tag_count desc limit 100;"

echo "************Array Text***********"
docker exec ali psql -U postgres -c "EXPLAIN ANALYZE select count(*) as tag_count, tag from doc_tags_array join tags on doc_tags_array.tags @> array[tags.tag::text]   group by tag  order by tag_count desc limit 100;"
echo "************text***********"
docker exec ali psql -U postgres -c "EXPLAIN ANALYZE select count(*) as tag_count,doc_tags_text.tag from doc_tags_text join tags on doc_tags_text.tag=tags.tag group by doc_tags_text.tag order by tag_count desc limit 100;"
echo "************ID***********"
docker exec ali psql -U postgres -c "EXPLAIN ANALYZE select count(*) as tag_count,tags.tag from doc_tags_id join tags on  doc_tags_id.tag_id=tags.tag_id group by tags.tag order by tag_count desc limit 100;"





exit 0 

