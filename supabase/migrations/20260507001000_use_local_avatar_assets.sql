do $mig$
declare
  target_table text;
begin
  if to_regclass('dungeonku.avatar_templates') is not null then
    target_table := 'dungeonku.avatar_templates';
  elsif to_regclass('public.avatar_templates') is not null then
    target_table := 'public.avatar_templates';
  else
    return;
  end if;

  execute format($sql$
    update %s as a
    set image_url = v.image_url
    from (values
      ('warrior_01', 'assets/images/avatars/warrior_01.png'),
      ('warrior_02', 'assets/images/avatars/warrior_02.png'),
      ('warrior_03', 'assets/images/avatars/warrior_03.png'),
      ('warrior_04', 'assets/images/avatars/warrior_04.png'),
      ('warrior_05', 'assets/images/avatars/warrior_05.png'),
      ('rogue_01', 'assets/images/avatars/rogue_01.png'),
      ('rogue_02', 'assets/images/avatars/rogue_02.png'),
      ('rogue_03', 'assets/images/avatars/rogue_03.png'),
      ('rogue_04', 'assets/images/avatars/rogue_04.png'),
      ('rogue_05', 'assets/images/avatars/rogue_05.png'),
      ('mage_01', 'assets/images/avatars/mage_01.png'),
      ('mage_02', 'assets/images/avatars/mage_02.png'),
      ('mage_03', 'assets/images/avatars/mage_03.png'),
      ('mage_04', 'assets/images/avatars/mage_04.png'),
      ('mage_05', 'assets/images/avatars/mage_05.png'),
      ('priest_01', 'assets/images/avatars/priest_01.png'),
      ('priest_02', 'assets/images/avatars/priest_02.png'),
      ('priest_03', 'assets/images/avatars/priest_03.png'),
      ('priest_04', 'assets/images/avatars/priest_04.png'),
      ('priest_05', 'assets/images/avatars/priest_05.png'),
      ('ranger_01', 'assets/images/avatars/ranger_01.png'),
      ('ranger_02', 'assets/images/avatars/ranger_02.png'),
      ('ranger_03', 'assets/images/avatars/ranger_03.png'),
      ('ranger_04', 'assets/images/avatars/ranger_04.png'),
      ('ranger_05', 'assets/images/avatars/ranger_05.png'),
      ('blacksmith_01', 'assets/images/avatars/blacksmith_01.png'),
      ('blacksmith_02', 'assets/images/avatars/blacksmith_02.png'),
      ('blacksmith_03', 'assets/images/avatars/blacksmith_03.png'),
      ('blacksmith_04', 'assets/images/avatars/blacksmith_04.png'),
      ('blacksmith_05', 'assets/images/avatars/blacksmith_05.png')
    ) as v(id, image_url)
    where a.id = v.id
      and a.image_url is distinct from v.image_url;
  $sql$, target_table);
end
$mig$;
