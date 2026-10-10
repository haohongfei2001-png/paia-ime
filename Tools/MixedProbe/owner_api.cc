// Included by the standalone probe. No Swift/host evidence is claimed here.
namespace mixed_probe {
struct APIProbeOwner {
  uint64_t id=0;
  explicit APIProbeOwner(uint64_t source){require(mixed::open(source,&id)==PG_OK && id,"mixed owner open failed");}
  ~APIProbeOwner(){mixed::close(id);}
};
struct APIPage {PaiaMixedPage value{};~APIPage(){free_list(&value.result);}};
struct APIChoice {uint64_t proof;std::string surface;size_t end;};
APIChoice api_choose(uint64_t owner,const std::string& raw,const std::string& surface,size_t end) {
  APIPage page;require(mixed::project(owner,raw.data(),raw.size(),2048,&page.value)==PG_OK,"API projection failed");
  size_t index=2048;
  for(size_t i=0;i<page.value.result.count;++i){const auto& row=page.value.result.items[i];if(row.end_utf8==end && row.text==surface){index=row.index;break;}}
  require(index<2048,"API genuine candidate unavailable");
  PaiaMixedSelection selection{};require(mixed::select(owner,page.value.projection,index,&selection)==PG_OK,"API actual select failed");
  APIChoice result{selection.proof,selection.surface,selection.end_utf8};mixed::free_selection(&selection);return result;
}
void api_commit(uint64_t owner,const std::vector<PaiaMixedPart>& parts,const std::string& expected) {
  char *result=nullptr;
  require(mixed::commit(owner,parts.data(),parts.size(),2048,&result)==PG_OK && result,"API commit failed");
  const std::string actual(result);mixed::free_text(result);require(actual==expected,"API actual full commit differs");
  result=nullptr;require(mixed::commit(owner,parts.data(),parts.size(),2048,&result)==PG_INVALID && !result,"API successful receipt replayed");
}
void owner_api_probe() {
  OwnedSession source;create(source,"paia_b1_full_ascii",{},"nihaoshijie");const auto before=witness(source.id);int commits=0;
  for(bool rightFirst:{false,true})for(const auto& literal:std::vector<std::string>{"RAG","data","user_id","3.14","https://example.test/a_b?q=1.2","👩🏽‍💻","é","𠀀"}) {
    APIProbeOwner owner(source.id);APIChoice left{},right{};
    if(rightFirst){right=api_choose(owner.id,"hao","好",3);left=api_choose(owner.id,"ni","你",2);}
    else{left=api_choose(owner.id,"ni","你",2);right=api_choose(owner.id,"hao","好",3);}
    std::vector<PaiaMixedPart> parts={{"ni",2,left.proof},{literal.data(),literal.size(),0},{"hao",3,right.proof}};
    char *failed=nullptr;require(mixed::commit(owner.id,parts.data(),parts.size(),0,&failed)==PG_INCOMPLETE && !failed,"API budget failure not isolated");
    api_commit(owner.id,parts,"你"+literal+"好");++commits;
  }
  {APIProbeOwner owner(source.id);auto left=api_choose(owner.id,"nihao","你",2);require(left.end==2,"API partial coverage lost");auto right=api_choose(owner.id,"hao","好",3);
   api_commit(owner.id,{{"ni",2,left.proof},{"RAG",3,0},{"hao",3,right.proof}},"你RAG好");++commits;}
  {APIProbeOwner a(source.id),b(source.id);APIPage pageA,pageB;
   require(mixed::project(a.id,"ni",2,2048,&pageA.value)==PG_OK && mixed::project(b.id,"ni",2,2048,&pageB.value)==PG_OK,"API identity setup failed");
   PaiaMixedSelection selection{};require(mixed::select(a.id,pageB.value.projection,0,&selection)==PG_INVALID,"foreign projection accepted");
   auto first=api_choose(a.id,"ni","你",2),second=api_choose(b.id,"ni","你",2);require(first.proof!=second.proof,"proof identity reused");
   char *text=nullptr;PaiaMixedPart foreign{"ni",2,second.proof};require(mixed::commit(a.id,&foreign,1,2048,&text)==PG_INVALID && !text,"foreign proof accepted");
   mixed::forget(a.id,first.proof);PaiaMixedPart forgotten{"ni",2,first.proof};require(mixed::commit(a.id,&forgotten,1,2048,&text)==PG_INVALID,"revoked proof accepted");
   require(mixed::select(a.id,pageA.value.projection,0,&selection)==PG_INVALID,"stale projection accepted");
   api_commit(b.id,{{"ni",2,second.proof}},"你");++commits;}
  {APIProbeOwner owner(source.id);APIPage page;const char invalid[]={'a',0,'b'};
   require(mixed::project(owner.id,invalid,3,2048,&page.value)==PG_INVALID,"embedded NUL accepted");
   const char invalidUTF8[]={char(0xed),char(0xa0),char(0x80)};char *text=nullptr;
   PaiaMixedPart malformed{invalidUTF8,3,0};require(mixed::commit(owner.id,&malformed,1,2048,&text)==PG_INVALID,"surrogate UTF8 accepted");
   const std::string literal="é👩🏽‍💻𠀀";api_commit(owner.id,{{literal.data(),literal.size(),0}},literal);++commits;}
  // Explicit 128-proof long suffix, not 128 uses of one token or fabricated text.
  {APIProbeOwner owner(source.id);std::vector<PaiaMixedPart> parts={{"RAG",3,0}};std::string expected="RAG";
   for(int i=0;i<128;++i){auto proof=api_choose(owner.id,"shijie","世界",6);parts.push_back({"shijie",6,proof.proof});expected+="世界";}
   api_commit(owner.id,parts,expected);++commits;}
  require(witness(source.id)==before,"API probe mutated original source");
  std::cout<<"MIXED_OWNER_API commits="<<commits<<" exact native full effects; left/right order, partial raw, global capabilities, explicit lengths, budget retry and sealed receipt; no host\n";
}
}
