function [] = MILP(flow,data,alpha)

NF=length(flow);

%% decision variable
x=optimvar('x',NF,length(data.edge_cloud),'Type','integer',...
    'LowerBound',0,'UpperBound',1);

pi=optimvar('pi',NF,length(data.access_router),length(data.edge_cloud),...
    'Type','integer','LowerBound',0,'UpperBound',1);

t=optimvar('t',length(data.edge_cloud),'LowerBound',0);

y=optimvar('y',NF,length(data.edge_cloud),'LowerBound',0);

z=optimvar('z',size(data.graph.Edges,1),'LowerBound',0);

omega=optimvar('omega',size(data.graph.Edges,1),NF,length(data.access_router),...
    length(data.edge_cloud),'LowerBound',0);

%% constraints
%ec_cache_num_constr
ec_cache_num_constr=sum(x,2)<=data.N_k;

%ec_cache_space_constr
ec_cache_space_constr=data.W_k*x<=data.Zeta_e;

%total_cache_space_constr
total_cache_space_constr=sum(data.W_k*x,2)<=data.Zeta_t;

%linear_denominator_constr
linear_denominator_constr=data.Zeta_e.*t'-data.W_k*y==1;

%sufficiently large number
M1=1;
M2=100000;

%y_define_constr
t_y=repmat(t',[NF,1]);
y_define_constr1=y<=t_y;
y_define_constr2=y<=M1*x;
y_define_constr3=y>=M1*(x-1)+t_y;

%pi_define_constr
x_pi=repmat(x,[length(data.access_router),1,1]);
x_pi=reshape(x_pi,NF,length(data.access_router),length(data.edge_cloud));
pi_define_constr1=pi<=x_pi;

pi_define_constr2=sum(pi,3)>=sum(x_pi,3);

%link_delay_constr
R_komega=repmat(data.R_k,[size(data.graph.Edges,1),1,...
    length(data.access_router),length(data.edge_cloud)]);

[m,n,l]=size(pi);
pi_omega=reshape(pi,1,m*n*l);
pi_omega=repmat(pi_omega,[size(data.graph.Edges,1),1]);
pi_omega=reshape(pi_omega,size(data.graph.Edges,1),m,n,l);

beta=GetPathLinkRel(data.graph,"undirected",data.path,length(data.access_router),...
    length(data.edge_cloud));
[m,n,l]=size(beta);
beta_omega=reshape(beta,1,m*n*l);
beta_omega=repmat(beta_omega,[NF,1]);
beta_omega=reshape(beta_omega,NF,m,n,l);
beta_omega=permute(beta_omega,[2,1,3,4]);

link_delay_constr=data.C_l*z-sum(sum(sum(R_komega.*omega.*beta_omega,2),3),4)>=1;

%link_slack_constr
%delta_link=GetWorstLinkDelay(data.C_l,data.R_k,data.path);
delta_link=data.delta*2/3;
link_slack_constr=sum(sum(sum(beta_omega.*omega,4),3),1)<=delta_link;

%omega_define_constr
z_omega=repmat(z,[1,NF,length(data.access_router),length(data.edge_cloud)]);
omega_define_constr1=omega<=z_omega;
omega_define_constr2=omega<=M2*pi_omega;
omega_define_constr3=omega>=M2*(pi_omega-1)+z_omega;

%edge_delay_constr
% in practice, use min() to replace the delta_edge not effect the result
delta_edge=min(data.delta*1/3);
lammax=GetMaxLambda(data.mu,data.ce,delta_edge);
edge_delay_constr=sum(x,1)<=lammax;

%% create optimization problem and objective function

ProCache=optimproblem;

objfun1=sum(alpha*data.W_e*y,2);

probability_pi=repmat(data.probability,[1,1,length(data.edge_cloud)]);
w_pi=cell2mat(data.cost);
[m,n]=size(w_pi);
w_pi=reshape(w_pi,1,m*n);
w_pi=repmat(w_pi,[NF,1]);
w_pi=reshape(w_pi,NF,m,n);

objfun2=sum(sum(probability_pi.*w_pi.*pi,3),2);

punish=log(max(data.delta)+50-data.delta)*500;

objfun3=(1-sum(sum(probability_pi.*pi,3),2)).*punish';

ProCache.Objective=sum(objfun1+objfun2+objfun3);

ProCache.Constraints.ec_cache_num_constr1=ec_cache_num_constr;
ProCache.Constraints.ec_cache_space_constr=ec_cache_space_constr;
ProCache.Constraints.total_cache_space_constr=total_cache_space_constr;
ProCache.Constraints.linear_denominator_constr=linear_denominator_constr;
ProCache.Constraints.y_define_constr1=y_define_constr1;
ProCache.Constraints.y_define_constr2=y_define_constr2;
ProCache.Constraints.y_define_constr3=y_define_constr3;
ProCache.Constraints.pi_define_constr1=pi_define_constr1;
ProCache.Constraints.pi_define_constr2=pi_define_constr2;
ProCache.Constraints.link_delay_constr=link_delay_constr;
ProCache.Constraints.link_slack_constr=link_slack_constr;
ProCache.Constraints.omega_define_constr1=omega_define_constr1;
ProCache.Constraints.omega_define_constr2=omega_define_constr2;
ProCache.Constraints.omega_define_constr3=omega_define_constr3;
ProCache.Constraints.edge_delay_constr=edge_delay_constr;

%% solve the problem using MILP

opts=optimoptions('intlinprog','Display','off');

% timer for MILP
tic;
[sol,fval,exitflag,output]=solve(ProCache,'Options',opts);
MILP_time=toc;

if isempty(sol)
    disp('The solver did not return a solution.')
    return
end

%caculate the number of constrains
buff=struct2cell(ProCache.Constraints);
counter_constraints=0;
for ii=1:numel(buff)
    counter_constraints=counter_constraints+numel(buff{ii});
end
fprintf('The total number of constraints are %d.\n', counter_constraints);

%examine the sol
bool_buff=zeros(numel(buff),1);
for ii=1:numel(buff)
    if max(infeasibility(buff{ii},sol))<=output.constrviolation
        bool_buff(ii)=1;
    end
end
if (exitflag=="OptimalSolution")&&(all(bool_buff==1))
    disp('the solution is feasible')
else
    disp('the solution is not feasible')
end

%% return of MILP, to be continued...

[s1,t1]=find(round(sol.x));

[BB,II]=sort(s1);
t1=t1(II);

% for ii=1:NF
%     fprintf("for flow %d , cache in edgecloud %d \n", ii, edge_cloud(t1(ii)));
% end
[B,I]=sort(probability_ka,2,'descend');
ar_list=I(:,1);

total_cost=CostCalculator(t1,ar_list,W_k,probability_ka,...
    Zeta_e,W_e,Zeta_t,utilization,G_full,alpha,punish,edge_cloud,server);

delay_time = TimeCalculator(t1,path,R_k,C_l,lambda,mu,ce,Tpr,edge_cloud,server);
fprintf("delay time is %f\n",delay_time);
result(1,9)=delay_time;

if delay_time > delta
    total_cost_add=total_cost+penalty*punish*(delay_time-delta);
    fprintf("original cost is %f, penalty is %f",total_cost,...
        total_cost_add-total_cost);
else
    total_cost_add=total_cost;
end

fprintf("total cost is %f\n ",total_cost_add);
result(1,3)=total_cost_add;

display(MILP_time);
result(1,15)=MILP_time;
end
