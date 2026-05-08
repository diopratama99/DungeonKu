do $mig$
declare
  target_table text;
begin
  if to_regclass('dungeonku.story_templates') is not null then
    target_table := 'dungeonku.story_templates';
  elsif to_regclass('public.story_templates') is not null then
    target_table := 'public.story_templates';
  else
    return;
  end if;

  execute format($sql$
    update %s as s
    set cover_image_url = v.cover_image_url
    from (values
      ('the_sunken_crown', 'assets/images/campaigns/covers/the_sunken_crown.png'),
      ('ashfall', 'assets/images/campaigns/covers/ashfall.png'),
      ('the_clockwork_heist', 'assets/images/campaigns/covers/the_clockwork_heist.png')
    ) as v(id, cover_image_url)
    where s.id = v.id
      and s.cover_image_url is distinct from v.cover_image_url;
  $sql$, target_table);
end
$mig$;
