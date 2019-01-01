% This class is derived from:
%
% An implementation of direct collocation
% Joel Andersson, 2016
% https://github.com/casadi/casadi/blob/master/docs/examples/matlab/direct_collocation.m
%
% CasADi -- A symbolic framework for dynamic optimization.
% Copyright (C) 2010-2014 Joel Andersson, Joris Gillis, Moritz Diehl,
%                         K.U. Leuven. All rights reserved.
% Copyright (C) 2011-2014 Greg Horn
% Under GNU Lesser General Public License

classdef CollocationIntegrator < handle
  
  properties
    system
    integratorFun
    ocpHandler
    varsStruct
    nx
    nz
  end
  
  properties(Access = private)
    d
    B
    C
    D  
    tau_root
  end
  
  
  methods
    
    function self = CollocationIntegrator(system,d)
      
      self.system = system;
      self.d = d;
      self.nx = prod(system.statesStruct.size());
      self.nz = prod(system.algVarsStruct.size());
      
      self.tau_root = collocationPoints(d);
      [self.C,self.D,self.B] = self.getCoefficients(d);
      
      self.varsStruct = OclTree();
      self.varsStruct.addRepeated({'states','algVars'},...
                                  {self.system.statesStruct,self.system.algVarsStruct},...
                                  self.d);
      
      sx = system.statesStruct.size();
      si = self.varsStruct.size();
      su = system.controlsStruct.size();
      sp = system.parametersStruct.size();
      st = [1,1];
      
      fh = @(self,varargin)self.getIntegrator(varargin{:});
      self.integratorFun = OclFunction(self, fh, {sx,si,su,st,st,st,sp}, 4);
                                                  
    end

    function [statesEnd, AlgVarsEnd, costs, equations] = getIntegrator(self,statesBegin,integratorVars,...
                                                                         controls,startTime,finalTime,endTime,parameters)
                                                                         
      h = finalTime-startTime;
      equations = cell(self.d,1);
      J = 0;
      
      % Loop over collocation points
      statesEnd = self.D(1)*statesBegin;
      for k=1:self.d
        
        k_vars = (k-1)*(self.nx+self.nz);
        i_states = k_vars+1:k_vars+self.nx;
        i_algVars = k_vars+self.nx+1:k_vars+self.nx+self.nz;

        xp = self.C(1,k+1)*statesBegin;
        for r=1:self.d
           xp = xp + self.C(r+1,k+1)*integratorVars(i_states);
        end

        time = startTime + self.tau_root(k+1) * h;

        % Append collocation equations
        [ode,alg] = self.system.systemFun.evaluate(integratorVars(i_states), ...
                                                   integratorVars(i_algVars), ...
                                                   controls,parameters);
        equations{k} = [h*ode-xp; alg];

        % Add contribution to the end state
        statesEnd = statesEnd + self.D(k+1)*integratorVars(i_states);

        % Add contribution to quadrature function
        qj = self.ocpHandler.pathCostsFun.evaluate(integratorVars(i_states),integratorVars(i_algVars),controls,time,endTime,parameters);
        J = J + self.B(k+1)*qj*h;
      end

      AlgVarsEnd = integratorVars(i_algVars);
      costs = J;
      equations = vertcat(equations{:});
    end
  end

  methods (Access = private)

    function [C,D,B] = getCoefficients(self, d)
      
      % Coefficients of the collocation equation
      C = zeros(d+1,d+1);

      % Coefficients of the continuity equation
      D = zeros(d+1, 1);

      % Coefficients of the quadrature function
      B = zeros(d+1, 1);

      % Construct polynomial basis
      for j=1:d+1
        % Construct Lagrange polynomials to get the polynomial basis at the collocation point
        coeff = 1;
        for r=1:d+1
          if r ~= j
            coeff = conv(coeff, [1, -self.tau_root(r)]);
            coeff = coeff / (self.tau_root(j)-self.tau_root(r));
          end
        end
        % Evaluate the polynomial at the final time to get the coefficients of the continuity equation
        D(j) = polyval(coeff, 1.0);

        % Evaluate the time derivative of the polynomial at all collocation points to get the coefficients of the continuity equation
        pder = polyder(coeff);
        for r=1:d+1
          C(j,r) = polyval(pder, self.tau_root(r));
        end

        % Evaluate the integral of the polynomial to get the coefficients of the quadrature function
        pint = polyint(coeff);
        B(j) = polyval(pint, 1.0);
      end
    end
    
  end
  
end

