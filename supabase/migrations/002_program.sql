-- Body volebního programu pro Hlídač slibů.
-- Před spuštěním zkontrolujte, že sedí se zveřejněným programem.
-- Všechny body začínají ve stavu „nezahájeno“; stav se mění jen v aplikaci, s poznámkou.

with ch(pos, title, items) as (values
 (1, 'Bezpečná obec — doprava s rozumem', array[
   'Sčítání dopravy a měření hluku a prašnosti na průtazích',
   'Zklidnění podle dat: úpravy vjezdů, ostrůvky, nasvícené přechody, radary a kontroly policie',
   'Tranzit na tangentu a D3, ne přes náves',
   'Souvislé bezbariérové chodníky v každé osadě a bezpečné spojení mezi nimi',
   'Posílení MHD ve špičce i o víkendu a důstojné zastávky']),
 (2, 'Rozvoj s rozvahou', array[
   'Nejdřív dostavět, potom rozšiřovat zastavitelné plochy',
   'U každého většího záměru doložit dopady na dopravu, školu, vodu a kanalizaci',
   'Jasná a stejná pravidla: limity zastavěnosti, podíl zeleně, parkování na pozemku investora',
   'Kdo staví ve velkém, podílí se na infrastruktuře, kterou zatíží',
   'Změny územního plánu projednávat veřejně a s předstihem']),
 (3, 'Otevřená radnice', array[
   'Videozáznamy zasedání zastupitelstva na webu obce',
   'Veřejná projednání dřív, než je věc rozhodnutá',
   'Srozumitelný rozpočet a přehled zakázek: kolik, komu a proč',
   'Ankety u témat, která se dotýkají všech, s vždy zveřejněným výsledkem',
   'Dny otevřených dveří a setkání se zastupiteli v každé ze tří osad']),
 (4, 'Živá komunita a služby blízko domovu', array[
   'Předvídatelná podpora spolků a společný kalendář akcí ve všech třech osadách',
   'Bankomat v obci a rozšíření zdravotní péče',
   'Kapacita školy a školky drží krok s výstavbou',
   'Bezpečná pěší a cyklistická cesta mezi osadami',
   'Senioři: senior taxi, obědy včetně rozvozu, bezbariérové trasy, klub seniorů']),
 (5, 'Sport a volný čas', array[
   'Dostavba sportovního areálu v Mokrém s harmonogramem a zveřejněnými náklady',
   'Přednost obyvatel obce při využití sportovišť, stabilní podpora klubů a mládeže',
   'Hřiště, workout a běžecký okruh zdarma v každé osadě',
   'Cyklostezky jako doprava: propojení osad, Stromovky a Českých Budějovic',
   'Knihovna, kroužky a prostor pro mládež']),
 (6, 'Zelené Litvínovice', array[
   'Prověřit, jak zvýšit ochranu Litvínovických rybníků jako lokálního biocentra',
   'Voda v krajině: tůně, mokřady, revitalizace břehů, remízky a meze',
   'Méně plošného sekání, více stromů, alejí a kvetoucích ploch',
   'Úspory energie, fotovoltaika na obecních budovách a sdílení energie',
   'Veřejný prostor: stín, lavičky, pitná voda, koše a pořádek',
   'Srozumitelný systém odpadů a férová motivace k třídění']),
 (7, 'Silný soused', array[
   'Pravidelná jednání s Českými Budějovicemi, sousedními obcemi a krajem',
   'Zastoupení obce v kraji, ŘSD, svazcích obcí a místní akční skupině',
   'Společný postup v dopravě: navazující cyklostezky, MHD, koordinace uzavírek',
   'Včasné hlídání připravovaných záměrů v okolí'])
), ins as (
  insert into public.chapters (position, title) select pos, title from ch returning id, position
)
insert into public.promises (chapter_id, position, text)
select ins.id, i.ord, i.txt
from ins join ch on ch.pos = ins.position
cross join lateral unnest(ch.items) with ordinality as i(txt, ord);
